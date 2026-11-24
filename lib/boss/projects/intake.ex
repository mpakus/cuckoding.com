defmodule Boss.Projects.Intake do
  @moduledoc "An explicit, persisted documentation plan that hands off to the normal Autopilot."
  import Ecto.Query
  alias Boss.{Deliveries, Projects, Repo, Runs}
  alias Boss.Deliveries.{Autopilot, AutopilotBatch}
  alias Boss.Projects.{Project, Spec}
  alias Boss.Projects.Intake.{Attempts, Planner, Request}

  def start(project, command, text, reviewer, server_or_loop \\ Runs.Manager)

  def start(project, command, text, reviewer, spec_loop) when is_boolean(spec_loop),
    do: start(project, command, text, reviewer, spec_loop, Runs.Manager)

  def start(project, command, text, reviewer, server),
    do: start(project, command, text, reviewer, nil, server)

  def start(project, command, text, reviewer, spec_loop, server),
    do:
      GenServer.call(
        server,
        {:project_intake_start, project, command, text, reviewer, spec_loop, nil},
        10_000
      )

  def replan(
        project,
        command,
        text,
        reviewer,
        spec_loop,
        previous_intake_id,
        server \\ Runs.Manager
      )
      when is_boolean(spec_loop) and is_binary(previous_intake_id) do
    GenServer.call(
      server,
      {:project_intake_start, project, command, text, reviewer, spec_loop, previous_intake_id},
      10_000
    )
  end

  def latest(project) do
    from(r in Request, where: r.project_id == ^project, order_by: [desc: r.inserted_at], limit: 1)
    |> read_request()
    |> with_brief_status()
  end

  defp with_brief_status(nil), do: nil
  defp with_brief_status(%Request{start_policy: nil} = request), do: request

  defp with_brief_status(request) do
    brief_task =
      Repo.one(
        from a in "project_brief_tasks",
          join: t in Boss.Tasks.Task,
          on: t.id == a.task_id,
          where: a.intake_id == ^request.id,
          select: %{id: t.id, state: t.state}
      )

    %{request | replan_source_id: replan_source(request.project_id), brief_task: brief_task}
  end

  defp replan_source(project) do
    Repo.one(
      from v in "project_brief_replan_sources",
        where: v.project_id == ^project,
        select: v.intake_id
    )
  end

  def policy(id) do
    request = read_request(from r in Request, where: r.id == ^id)

    case request && request.start_policy do
      nil ->
        nil

      %{"version" => 1, "spec_loop" => loop, "parallel" => parallel} ->
        %{version: 1, spec_loop: loop, parallel: parallel}
    end
  end

  defp read_request(query) do
    if policy_schema?(),
      do: Repo.one(from r in query, select_merge: %{start_policy: r.start_policy}),
      else: Repo.one(query)
  end

  defp policy_schema? do
    Repo.query!("SELECT 1 FROM pragma_table_info('project_intakes') WHERE name='start_policy'").rows !=
      []
  end

  def ensure_brief_selection!(project, tasks, hash, reviewer) do
    if policy_schema?() and
         Repo.exists?(
           from b in "project_brief_tasks",
             join: i in Request,
             on: i.id == b.intake_id,
             where:
               i.project_id == ^project and b.task_id in ^tasks and
                 (i.config_hash != ^hash or i.reviewer != ^reviewer)
         ),
       do: Repo.rollback(:brief_policy_mismatch)
  end

  def attempts(id), do: Attempts.list(id)
  def begin_attempt(id), do: Attempts.begin(id)
  def finish_attempt(id, receipt), do: Attempts.finish(id, receipt)
  def plan_hash(tasks), do: Attempts.plan_hash(tasks)

  def topic(project), do: "project-intake:#{project}"

  def stop(project, id) do
    Runs.stop(project, {:intake, id})

    case transaction(fn ->
           case Repo.get_by(Request, id: id, project_id: project) do
             %Request{status: "planning"} = request ->
               save!(request, stop_requested: true)
               :stopping

             %Request{batch_id: batch} when is_binary(batch) ->
               {:batch, batch}

             %Request{} ->
               :stopping

             nil ->
               Repo.rollback(:not_found)
           end
         end) do
      {:ok, :stopping} ->
        :ok

      {:ok, {:batch, batch}} ->
        case Autopilot.cancel(project, batch, 0) do
          {:ok, _} -> :ok
          error -> error
        end

      error ->
        error
    end
  end

  @doc false
  def batch_allowed?(id, project, command, config, hash, reviewer, opts \\ [])
  def batch_allowed?(nil, _, _, _, _, _, _), do: not busy?()

  def batch_allowed?(id, project, command, config, hash, reviewer, opts) do
    authorized =
      case policy(id) do
        nil ->
          true

        %{parallel: parallel, spec_loop: loop} ->
          Keyword.get(opts, :parallel, false) == parallel and
            Keyword.get(opts, :spec_loop, false) == loop and
            Keyword.get(opts, :max_passes, 2) == 2 and
            Keyword.get(opts, :loop_pass, 1) == 1 and
            Keyword.get(opts, :parent_autopilot_id) == nil
      end

    authorized and
      Repo.exists?(
        from r in Request,
          where:
            r.id == ^id and r.project_id == ^project and r.command_id == ^command and
              r.check_config == ^config and r.config_hash == ^hash and r.reviewer == ^reviewer and
              r.status == "planning" and not r.stop_requested and
              (r.planning_version == 0 or
                 fragment(
                   "EXISTS (SELECT 1 FROM project_intake_attempts a WHERE a.request_id=? AND a.status='finished' AND a.source_base=json_extract(?, '$.base_commit') AND a.number=(SELECT max(number) FROM project_intake_attempts WHERE request_id=?))",
                   r.id,
                   r.workspace,
                   r.id
                 ))
      )
  end

  def quarantined?, do: Repo.exists?(from r in Request, where: r.cleanup == "unknown")

  def busy?,
    do: Repo.exists?(from r in Request, where: r.status == "planning" or r.cleanup == "unknown")

  def admit(project, command, text, reviewer, owned, spec_loop \\ nil, previous_intake_id \\ nil) do
    with true <- is_nil(spec_loop) or is_boolean(spec_loop),
         true <-
           is_nil(previous_intake_id) or
             match?({:ok, ^previous_intake_id}, Ecto.UUID.cast(previous_intake_id)),
         true <-
           is_integer(project) and project > 0 and Boss.Agents.Metadata.review_runner?(reviewer),
         {:ok, ^command} <- Ecto.UUID.cast(command),
         {:ok, config, hash} <- Boss.Checks.Command.parse_workflow(text) do
      transaction(fn ->
        case read_request(
               from r in Request, where: r.project_id == ^project and r.command_id == ^command
             ) do
          %Request{check_config: ^config, config_hash: ^hash, reviewer: ^reviewer} = request ->
            matches =
              case request.start_policy do
                nil ->
                  is_nil(spec_loop) and is_nil(previous_intake_id)

                %{"spec_loop" => saved} = policy ->
                  saved == (spec_loop || false) and
                    policy["previous_intake_id"] == previous_intake_id
              end

            if matches, do: {:existing, request}, else: Repo.rollback(:idempotency_conflict)

          %Request{} ->
            Repo.rollback(:idempotency_conflict)

          nil ->
            start_policy =
              cond do
                policy_schema?() ->
                  if Boss.Checks.Command.spec_only?(config),
                    do: Repo.rollback(:brief_check_required)

                  %{
                    "version" => 1,
                    "spec_loop" => spec_loop || false,
                    "previous_intake_id" => previous_intake_id,
                    "parallel" => Projects.RoleBindings.implementer_pool_size(project) > 1
                  }

                is_nil(spec_loop) and is_nil(previous_intake_id) ->
                  nil

                true ->
                  Repo.rollback(:storage_error)
              end

            unless match?(%Project{intake_mode: "documentation"}, Repo.get(Project, project)),
              do: Repo.rollback(:invalid_project)

            if owned or busy?() or Deliveries.busy?() or Autopilot.running?() or
                 Repo.exists?(from b in AutopilotBatch, where: b.status == "paused") or
                 Repo.exists?(
                   from r in Runs.Run,
                     where:
                       r.status in ~w(preparing launching running stopping) or
                         r.cleanup == "unknown"
                 ),
               do: Repo.rollback(:busy)

            ensure_plannable!(project, previous_intake_id)

            {:new,
             Repo.insert!(%Request{
               id: Ecto.UUID.generate(),
               project_id: project,
               command_id: command,
               check_config: config,
               config_hash: hash,
               reviewer: reviewer,
               autonomy_version: Boss.Deliveries.ModelPolicy.current(),
               routing_version: Boss.Deliveries.ModelPolicy.current_routing(),
               planning_version: 1,
               start_policy: start_policy,
               check_text: text
             })}
        end
      end)
    else
      _ -> {:error, :invalid_command}
    end
  end

  defp ensure_plannable!(project, nil) do
    if Repo.exists?(from r in Request, where: r.project_id == ^project and r.status == "finished") or
         Repo.exists?(
           from s in Spec,
             where:
               s.project_id == ^project and
                 fragment(
                   "NOT EXISTS (SELECT 1 FROM project_documentation_sources refs WHERE refs.spec_id=?)",
                   s.id
                 )
         ),
       do: Repo.rollback(:already_planned)
  end

  defp ensure_plannable!(project, previous_intake_id) do
    unless replan_source(project) == previous_intake_id, do: Repo.rollback(:replan_unavailable)
  end

  def pin(id, workspace) do
    case transaction(fn ->
           case Repo.get(Request, id) do
             %Request{status: "planning", stop_requested: true} ->
               Repo.rollback(:cancelled)

             %Request{status: "planning", workspace: empty} = request when empty == %{} ->
               unless request.routing_version == 1 or
                        Boss.Agents.Roles.analytic(
                          Boss.Agents.Roles.implementer(request.project_id),
                          request.project_id
                        ) != "codex" or
                        Boss.Agents.ModelCatalog.validate(request.model_catalog) == :ok,
                      do: Repo.rollback(:catalog_invalid)

               save!(request, workspace: workspace)

             _ ->
               Repo.rollback(:invalid_intent)
           end
         end) do
      {:ok, _} -> :ok
      error -> error
    end
  end

  def set_model_catalog(id, snapshot) do
    transaction(fn ->
      case Repo.get(Request, id) do
        %Request{status: "planning", stop_requested: true} ->
          Repo.rollback(:cancelled)

        %Request{status: "planning", routing_version: 2} = request ->
          unless Boss.Agents.ModelCatalog.validate(snapshot) == :ok,
            do: Repo.rollback(:catalog_invalid)

          cond do
            request.model_catalog == snapshot -> request
            request.model_catalog != %{} -> Repo.rollback(:immutable_model_catalog)
            request.workspace != %{} -> Repo.rollback(:invalid_intent)
            true -> save!(request, model_catalog: snapshot)
          end

        _ ->
          Repo.rollback(:invalid_intent)
      end
    end)
  end

  def execute(request, repo, manager) do
    Repo.put_dynamic_repo(repo)

    result =
      try do
        project = Repo.get!(Project, request.project_id)

        with {:ok, result} <- Planner.run(project, request.id),
             :ok <- Planner.validate_current(project, result),
             :ok <- continue() do
          case commit_plan(request.id, result) do
            {:ok, _} = saved -> saved
            {:error, :storage_error} = error -> error
            {:error, reason} -> fail(request.id, reason)
          end
        else
          {:error, reason} -> fail(request.id, reason)
        end
      rescue
        _ -> fail(request.id, :cleanup_unknown)
      catch
        :throw, {:halt, reason} -> fail(request.id, reason)
        _, _ -> fail(request.id, :cleanup_unknown)
      end

    send(manager, {:intake_finished, request.id, self(), result})
  end

  def interrupt(id), do: fail(id, :cleanup_unknown)

  def reconcile do
    transaction(fn ->
      Repo.all(from r in Request, where: r.status == "planning")
      |> Enum.map(fn request ->
        Attempts.interrupt!(request.id)

        save!(request,
          status: "interrupted",
          cleanup: "unknown",
          reason: message(:cleanup_unknown)
        )
      end)
    end)
    |> case do
      {:ok, requests} = result ->
        Enum.each(requests, &broadcast/1)
        result

      error ->
        error
    end
  end

  def broadcast(request) do
    Phoenix.PubSub.broadcast(
      Boss.PubSub,
      topic(request.project_id),
      {:project_intake, request.project_id}
    )

    Runs.broadcast(request)
  end

  def initial_base(batch_id) do
    case Repo.get_by(Request, batch_id: batch_id) do
      %Request{workspace: %{"base_commit" => sha}} ->
        sha

      nil ->
        case loop_source(batch_id) do
          %{ancestor_published: false, base: base} -> base
          _ -> nil
        end
    end
  end

  def loop_source(batch_id) do
    if policy_schema?() do
      # Follow only linked passes. The initial base holds until an ancestor publishes,
      # while the trusted check text stays pinned throughout the loop.
      case Repo.query!(
             """
             WITH RECURSIVE lineage(id,published) AS (
               SELECT ?,0
               UNION ALL
               SELECT parent.autopilot_id,lineage.published OR EXISTS (
                 SELECT 1 FROM autopilot_items i JOIN delivery_requests r ON r.id=i.request_id
                 JOIN deliveries d ON d.id=r.delivery_id WHERE i.autopilot_id=parent.autopilot_id AND d.status='done'
               ) FROM lineage JOIN autopilot_loop_configs child ON child.autopilot_id=lineage.id
               JOIN autopilot_loop_configs parent ON parent.autopilot_id=child.parent_autopilot_id
                 AND parent.next_autopilot_id=child.autopilot_id AND parent.loop_pass+1=child.loop_pass
             )
             SELECT json_extract(i.workspace,'$.base_commit'),i.check_text,lineage.published FROM lineage
             JOIN project_intakes i ON i.batch_id=lineage.id WHERE i.start_policy IS NOT NULL LIMIT 1
             """,
             [batch_id]
           ).rows do
        [[base, text, published]] ->
          %{base: base, check_text: text, ancestor_published: published == 1}

        [] ->
          nil
      end
    end
  end

  def expected_delivery_base(delivery) do
    with batch when is_binary(batch) <- Autopilot.owner(delivery),
         base when is_binary(base) <- initial_base(batch),
         false <-
           Repo.exists?(
             from i in Boss.Deliveries.AutopilotItem,
               join: r in Boss.Deliveries.Request,
               on: r.id == i.request_id,
               join: d in Boss.Deliveries.Delivery,
               on: d.id == r.delivery_id,
               where: i.autopilot_id == ^batch and d.id != ^delivery.id and d.status == "done"
           ) do
      base
    else
      _ -> nil
    end
  end

  defp commit_plan(id, %{workspace: workspace, tasks: tasks} = result) do
    transaction(fn ->
      request = read_request(from r in Request, where: r.id == ^id)

      unless request.status == "planning" and request.workspace == workspace,
        do: Repo.rollback(:invalid_intent)

      if request.stop_requested, do: Repo.rollback(:cancelled)
      accepted = Attempts.verified!(request, tasks)

      namespace =
        if get_in(request.start_policy, ["previous_intake_id"]) ||
             Boss.Projects.Documentation.latest(request.project_id),
           do: "intake-#{request.id}-",
           else: ""

      ids = Enum.map(tasks, &record_task!(request.project_id, workspace, &1, namespace))

      policy = policy(id)

      ids =
        if policy,
          do: Projects.BriefAcceptance.append!(request, result, tasks, ids, namespace),
          else: ids

      case ids do
        [] ->
          save!(request,
            status: "finished",
            cleanup: "group_empty",
            accepted_attempt_id: accepted
          )

        _ ->
          loop_opts =
            case policy do
              %{parallel: parallel, spec_loop: loop} ->
                [parallel: parallel, spec_loop: loop]

              nil ->
                parallel = Projects.RoleBindings.implementer_pool_size(request.project_id) > 1
                [parallel: parallel, spec_loop: parallel]
            end

          with {:ok, batch} <-
                 Autopilot.admit(
                   request.project_id,
                   request.command_id,
                   ids,
                   request.check_text,
                   request.reviewer,
                   false,
                   request.id,
                   loop_opts
                 ) do
            save!(request,
              status: "finished",
              cleanup: "group_empty",
              batch_id: batch.id,
              accepted_attempt_id: accepted
            )
          else
            {:error, reason} -> Repo.rollback(reason)
          end
      end
    end)
  end

  defp record_task!(project, workspace, task, namespace) do
    id = namespace <> task["id"]
    deps = JSON.encode!(Enum.map(task["depends_on"], &(namespace <> &1)))
    acceptance = Enum.map_join(task["acceptance"], "\n", &("- " <> &1))
    sources = Enum.map_join(task["sources"], "\n", &("- " <> &1))

    text = """
    ---
    depends_on: #{deps}
    ---
    # #{task["title"]}

    #{task["specification"]}

    ## Acceptance criteria
    #{acceptance}

    ## Source documents at #{workspace["base_commit"]}
    #{sources}
    """

    case Projects.record_spec(project, %{
           relative_path: "autopilot/#{id}.md",
           explicit_id: id,
           title: task["title"],
           original_text: text
         }) do
      {:ok, %{task: saved, change: :created}} -> saved.id
      _ -> Repo.rollback(:invalid_plan)
    end
  end

  defp fail(id, reason) do
    transaction(fn ->
      request = Repo.get!(Request, id)

      if request.status == "planning" do
        unfinished? = Attempts.interrupt!(request.id)

        if unfinished? or Attempts.unknown?(request.id) or
             reason in [:cleanup_unknown, :storage_error] do
          save!(request,
            status: "interrupted",
            cleanup: "unknown",
            reason: message(:cleanup_unknown)
          )
        else
          save!(request, status: "failed", cleanup: "group_empty", reason: message(reason))
        end
      else
        request
      end
    end)
  end

  defp message(:brief_unchanged),
    do: "The committed documentation is unchanged from the last completed brief."

  defp message(:cleanup_unknown),
    do: "Planning stopped without a verified cleanup receipt. Inspect the retained workspace."

  defp message(:target_checked_out),
    do: "The publication branch is checked out. Free it before starting Autopilot."

  defp message(:provider_startup),
    do:
      "Two different planning models failed before producing a valid report. Check the CLI and provider before starting again."

  defp message(:planning_deadline),
    do:
      "Documentation planning reached its saved time limit. Attempts remain available for inspection."

  defp message(:planning_attempts_exhausted),
    do:
      "Documentation planning exhausted its three attempts. Inspect the saved validation diagnostics."

  defp message(:models_exhausted),
    do: "No alternate model remains in the saved catalog for documentation planning."

  defp message(:cancelled), do: "Documentation planning stopped."
  defp message(:codex_unavailable), do: "Codex is unavailable on BOSS's PATH."
  defp message(:claude_unavailable), do: "Claude Code is unavailable on BOSS's PATH."
  defp message(:cursor_unavailable), do: "Cursor Agent is unavailable on BOSS's PATH."
  defp message(:opencode_unavailable), do: "OpenCode is unavailable on BOSS's PATH."

  defp message(:catalog_unavailable),
    do:
      "Codex could not provide its model catalog. Check the local CLI before starting planning again."

  defp message(:catalog_invalid),
    do: "Codex returned an invalid model catalog. No planning model was started."

  defp message(:catalog_insufficient_models),
    do:
      "The local model catalog has fewer than two eligible reasoning models. No planning model was started."

  defp message(:provider_auth),
    do:
      "The selected provider account could not authenticate. Restore its access before starting planning again."

  defp message(:provider_rate_limit),
    do:
      "The selected planning agent reported a rate, quota, or credit balance limit. Planning stopped without switching accounts."

  defp message(:provider_schema),
    do:
      "The provider rejected the request format. Update the adapter before starting planning again."

  defp message(:provider_transport),
    do:
      "Codex transport or protocol failed. Check the CLI, adapter and connection before starting planning again."

  defp message(_),
    do:
      "Documentation planning could not complete. Check the committed documents, target and provider."

  defp continue do
    receive do
      :stop -> {:error, :cancelled}
    after
      0 -> :ok
    end
  end

  defp save!(request, attrs), do: Repo.update!(Ecto.Changeset.change(request, attrs))

  defp transaction(fun) do
    Repo.transaction(fun, mode: :immediate)
  rescue
    _ in [Exqlite.Error, Ecto.ConstraintError, DBConnection.ConnectionError] ->
      {:error, :storage_error}
  catch
    :exit, _ -> {:error, :storage_error}
  end
end
