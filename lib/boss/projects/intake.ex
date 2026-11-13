defmodule Boss.Projects.Intake do
  @moduledoc "An explicit, persisted documentation plan that hands off to the normal Autopilot."
  import Ecto.Query
  alias Boss.{Deliveries, Projects, Repo, Runs}
  alias Boss.Deliveries.{Autopilot, AutopilotBatch}
  alias Boss.Projects.{Project, Spec}
  alias Boss.Projects.Intake.{Attempts, Planner, Request}

  def start(project, command, text, reviewer, server \\ Runs.Manager),
    do: GenServer.call(server, {:project_intake_start, project, command, text, reviewer}, 10_000)

  def latest(project) do
    Repo.one(
      from r in Request,
        where: r.project_id == ^project,
        order_by: [desc: r.inserted_at],
        limit: 1
    )
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
  def batch_allowed?(nil, _, _, _, _, _), do: not busy?()

  def batch_allowed?(id, project, command, config, hash, reviewer) do
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

  def admit(project, command, text, reviewer, owned) do
    with true <-
           is_integer(project) and project > 0 and Boss.Agents.Metadata.review_runner?(reviewer),
         {:ok, ^command} <- Ecto.UUID.cast(command),
         {:ok, config, hash} <- Boss.Checks.Command.parse(text) do
      transaction(fn ->
        case Repo.get_by(Request, project_id: project, command_id: command) do
          %Request{check_config: ^config, config_hash: ^hash, reviewer: ^reviewer} = request ->
            {:existing, request}

          %Request{} ->
            Repo.rollback(:idempotency_conflict)

          nil ->
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

            if Repo.exists?(
                 from r in Request, where: r.project_id == ^project and r.status == "finished"
               ) or
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
               check_text: text
             })}
        end
      end)
    else
      _ -> {:error, :invalid_command}
    end
  end

  def pin(id, workspace) do
    case transaction(fn ->
           case Repo.get(Request, id) do
             %Request{status: "planning", stop_requested: true} ->
               Repo.rollback(:cancelled)

             %Request{status: "planning", workspace: empty} = request when empty == %{} ->
               unless request.routing_version == 1 or
                        Boss.Agents.Roles.analytic(Boss.Agents.Roles.implementer()) != "codex" or
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
      %Request{workspace: %{"base_commit" => sha}} -> sha
      nil -> nil
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

  defp commit_plan(id, %{workspace: workspace, tasks: tasks}) do
    transaction(fn ->
      request = Repo.get!(Request, id)

      unless request.status == "planning" and request.workspace == workspace,
        do: Repo.rollback(:invalid_intent)

      if request.stop_requested, do: Repo.rollback(:cancelled)
      accepted = Attempts.verified!(request, tasks)

      namespace =
        if Boss.Projects.Documentation.latest(request.project_id),
          do: "intake-#{request.id}-",
          else: ""

      ids = Enum.map(tasks, &record_task!(request.project_id, workspace, &1, namespace))

      case ids do
        [] ->
          save!(request,
            status: "finished",
            cleanup: "group_empty",
            accepted_attempt_id: accepted
          )

        _ ->
          with {:ok, batch} <-
                 Autopilot.admit(
                   request.project_id,
                   request.command_id,
                   ids,
                   request.check_text,
                   request.reviewer,
                   false,
                   request.id
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
