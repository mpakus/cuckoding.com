defmodule Cuckoding.Battles.Snapshot do
  @moduledoc false
  alias Cuckoding.Battles.{
    Backoff,
    CandidateRecovery,
    Capacity,
    MixedClosure,
    PreparationRecovery,
    ProviderClosure,
    Slots,
    Stages,
    TaskBlocks,
    Waves
  }

  alias Cuckoding.{
    Agents,
    Codex,
    Command,
    Cursor,
    Foundation,
    GuestChecks,
    ProjectChecks,
    Repo,
    Tabulae,
    TaskChecks,
    TeamAssignments,
    Workflows
  }

  @roles ~w(speculator implementor secutor summa_rudis)
  @columns [
    {"specs", "speculator"},
    {"todo", "summa_rudis"},
    {"in_process", "implementor"},
    {"review", "secutor"},
    {"completed", nil}
  ]
  @limits %{
    "tasks" => 20,
    "review_rounds" => 3,
    "provider_retries" => 2,
    "turns" => 200,
    "wall_seconds" => 7200,
    "stage_seconds" => 900
  }

  # This function reads SQLite only. Native admission revalidates every recorded identity.
  def build(arena_id, tabula_id) do
    arena = Tabulae.arena(arena_id) || Repo.rollback(:scope_missing)
    board = Tabulae.get(arena.id, tabula_id) || Repo.rollback(:scope_missing)
    team = TeamAssignments.assigned(board)
    steps = Workflows.execution_stages(board.definition)
    step_roles = Enum.map(steps, & &1["role"])

    {execution, planning} =
      Enum.split_with(team.definition["roles"], &(&1["id"] in (@roles ++ step_roles)))

    execution =
      Enum.sort_by(execution, &Enum.find_index(@roles ++ step_roles, fn id -> id == &1["id"] end))

    roles = Enum.map(execution, &role_binding/1)

    additional =
      execution
      |> Enum.map(&Cuckoding.Team.additional/1)
      |> Enum.reject(&(&1["agent"] == ""))
      |> Enum.map(&role_binding/1)

    tasks = Enum.map(Tabulae.tasks(board.id), &task/1)
    checks = ProjectChecks.current(arena.id)
    {ordered, graph_valid?} = order(tasks, [])
    tasks = if graph_valid?, do: ordered, else: tasks
    planned = TaskChecks.freeze(tasks, checks.definition["checks"])
    invalid_verification? = match?({:error, _}, planned)

    planned =
      if invalid_verification?, do: %{"checks" => checks.definition["checks"]}, else: planned

    blockers =
      []
      |> block(tasks == [], "no_tasks")
      |> block(length(tasks) > @limits["tasks"], "task_limit")
      |> block(Enum.any?(tasks, &incomplete?/1), "incomplete_task")
      |> block(not graph_valid?, "invalid_dependencies")
      |> block(invalid_verification?, "invalid_task_verification")
      |> block(
        not prompt_scope?(tasks, planned["checks"], steps),
        "prompt_scope_too_large"
      )
      |> block(
        columns(board) != @columns or Enum.map(roles, & &1["id"]) != @roles ++ step_roles,
        "unsupported_columns"
      )
      |> check_blockers(planned["checks"], roles)
      |> Kernel.++(
        (roles ++ additional)
        |> Enum.map(& &1["status"])
        |> Enum.reject(&(&1 == "ready"))
      )
      |> Enum.uniq()

    snapshot = %{
      "version" => "arena-loop-v2",
      "recovery" => "provider-retry-v1",
      "provider_backoff" => Backoff.policy(),
      "scheduler" => Capacity.policy(),
      "parallelism" => Waves.policy(),
      "blocker_scope" => TaskBlocks.policy(),
      "role_slots" => Slots.policy(),
      "custom_stages" =>
        if(board.definition["version"] == 4, do: Stages.writer_policy(), else: Stages.policy()),
      "parallel_team" => additional,
      "native_recovery" => "retained-integration-v1",
      "worktree_recovery" => PreparationRecovery.policy(),
      "worktree_wave_recovery" => PreparationRecovery.wave_policy(),
      "candidate_recovery" => CandidateRecovery.policy(),
      "combination_recovery" => CandidateRecovery.combination_policy(),
      "mixed_closure" => MixedClosure.policy(),
      "provider_closure" => ProviderClosure.policy(),
      "timing_guard" => "elapsed-gap-v1",
      "idle_sleep" => "shell-lease-v1",
      "task_selection" => "skip-task-v1",
      "arena_id" => arena.id,
      "tabula_id" => board.id,
      "workflow_revision" => board.workflow_revision,
      "workflow_definition" => board.definition,
      "source" =>
        Map.new(~w(path device inode), &{&1, Map.fetch!(arena, String.to_existing_atom(&1))}),
      "team_revision" => team.id,
      "team" => roles,
      "tasks" => tasks,
      "check_revision" => checks.revision,
      "checks" => planned["checks"],
      "limits" => @limits
    }

    snapshot = Map.merge(snapshot, Map.drop(planned, ["checks"]))

    snapshot =
      if policy = GuestChecks.policy_for(snapshot["checks"]),
        do:
          Map.merge(snapshot, %{
            "check_execution" => policy,
            "check_feedback" => Cuckoding.CheckFeedback.policy()
          }),
        else: snapshot

    %{
      snapshot: snapshot,
      fingerprint: digest(snapshot),
      blockers: blockers,
      tasks: snapshot["tasks"],
      team: roles ++ additional,
      planning_roles: Enum.map(planning, &Map.take(&1, ~w(id name))),
      checks: snapshot["checks"],
      limits: @limits
    }
  end

  def digest(value), do: ProjectChecks.digest(value)

  def retained_tasks(snapshot, context) do
    omitted = Enum.map(context["omitted_tasks"] || [], & &1["id"])
    Enum.reject(snapshot["tasks"], &(&1["id"] in omitted))
  end

  def final_criteria_digest(snapshot, context) do
    criteria = Enum.map(retained_tasks(snapshot, context), & &1["criteria_sha256"])

    case context["omitted_tasks"] || [] do
      [] -> digest(criteria)
      omitted -> digest(%{"criteria" => criteria, "omitted_tasks" => omitted})
    end
  end

  # Only new, explicitly empty command scopes may omit host command stages.
  # Historical snapshots and any configured commands retain their original gates.
  def task_review_only?(%{"version" => "arena-loop-v2", "checks" => []}), do: true
  def task_review_only?(_), do: false

  defp block(reasons, true, reason), do: reasons ++ [reason]
  defp block(reasons, false, _), do: reasons

  defp columns(board),
    do:
      board.definition["columns"]
      |> Enum.reject(&Stages.custom_key?(&1["key"]))
      |> Enum.map(&{&1["key"], &1["role"]})

  defp check_blockers(blockers, checks, roles) do
    guest = not is_nil(GuestChecks.policy_for(checks))

    blockers
    |> block(check_limits?(checks), "check_timeout_limit")
    |> block(GuestChecks.mixed?(checks), "mixed_check_grants")
    |> block(guest and not GuestChecks.declarations_valid?(checks), "guest_check_scope_invalid")
    |> block(
      checks != [] and not guest and
        not Enum.any?(roles, &(&1["id"] == "implementor" and &1["kind"] == "codex")),
      "check_runtime_required"
    )
  end

  defp check_limits?(checks),
    do:
      Enum.any?(checks, &(&1["timeout_seconds"] > 300)) or
        Enum.sum(Enum.map(checks, & &1["timeout_seconds"])) > 600

  # Public summaries are byte-bounded at 4,000; escaping can double each byte.
  # Reserve the largest stage instruction and normalized check metadata without truncating input.
  defp prompt_scope?(tasks, checks, steps) do
    common = %{
      "contract" => "arena-stage-v1",
      "stage" => "final_secutor",
      "instruction" => String.duplicate("x", 2048),
      "prior_public_summary" => String.duplicate("\n", 4000),
      "workflow_findings" =>
        Enum.map(steps, &%{"stage" => &1["key"], "summary" => String.duplicate("\n", 512)}),
      "review_findings" => nil,
      "previous_implementation" => nil,
      "speculator_plan" => nil,
      "candidate_sha" => String.duplicate("a", 40),
      "host_checks" =>
        Enum.map(checks, &maximum_check(&1, not is_nil(GuestChecks.policy_for(checks)))),
      "declared_checks" => checks,
      "command_check_scope" => "not_configured",
      "result_scope" => "partial",
      "omitted_tasks" => Enum.map(tasks, &%{"id" => &1["id"], "state" => "deferred"}),
      "review_round" => 3,
      "local_result_reference" => "refs/heads/ccoding/battles/" <> String.duplicate("a", 36)
    }

    common =
      if GuestChecks.policy_for(checks),
        do: Map.put(common, "check_environment", GuestChecks.environment()),
        else: common

    task_metadata =
      Map.merge(common, %{
        "review_findings" => String.duplicate("\n", 4000),
        "previous_implementation" => String.duplicate("\n", 4000)
      })

    final = Enum.map(tasks, &Map.take(&1, ~w(id title criteria criteria_sha256 verification)))

    normal =
      Enum.all?(tasks, &task_prompts_fit?(&1, task_metadata)) and prompt_fits?(final, common)

    if GuestChecks.policy_for(checks) do
      feedback = %{
        "prior_public_summary" => nil,
        "check_feedback" => Cuckoding.CheckFeedback.reserve()
      }

      normal and Enum.all?(tasks, &task_prompts_fit?(&1, Map.merge(task_metadata, feedback))) and
        prompt_fits?(final, Map.merge(common, feedback))
    else
      normal
    end
  end

  defp task_prompts_fit?(task, metadata),
    do:
      prompt_fits?(task, metadata) and
        prompt_fits?(
          task,
          Map.merge(metadata, %{
            "previous_implementation" => nil,
            "speculator_plan" => String.duplicate("\n", 4000)
          })
        )

  defp maximum_check(check, true),
    do: Cuckoding.CheckFeedback.maximum_check(check)

  defp maximum_check(check, false),
    do: %{
      "id" => check["id"],
      "status" => "passed",
      "exit_code" => 255,
      "stdout_sha256" => String.duplicate("a", 64),
      "stdout_bytes" => 65_536,
      "pid" => 9_999_999_999_999,
      "spawned_at_ms" => 9_999_999_999_999,
      "elapsed_ms" => 310_000,
      "cleanup_verified" => false,
      "child_pid" => 9_999_999_999_999,
      "child_start_seconds" => 9_999_999_999_999,
      "child_start_microseconds" => 999_999
    }

  defp prompt_fits?(input, metadata),
    do:
      byte_size(Jason.encode!(input)) <= 24_576 and
        byte_size(Jason.encode!(Map.put(metadata, "task", input))) <= 32_768

  defp task(task) do
    Tabulae.content(task)
    |> Map.merge(%{
      "id" => task.id,
      "revision" => task.revision,
      "criteria_sha256" => TaskChecks.criteria_hash(task.criteria, task.verification)
    })
  end

  defp incomplete?(task),
    do: Enum.any?(~w(title description criteria), &(String.trim(task[&1]) == ""))

  defp order([], ordered), do: {ordered, true}

  defp order(tasks, ordered) do
    ready = Enum.map(ordered, & &1["id"])

    case Enum.find(tasks, fn task -> Enum.all?(task["depends_on"], &(&1 in ready)) end) do
      nil -> {ordered, false}
      task -> order(List.delete(tasks, task), ordered ++ [task])
    end
  end

  defp role_binding(role) do
    agent = Agents.get(role["agent"]) || %{id: nil, kind: nil, connection: %{}, codex: %{}}
    connection = agent.connection
    model = Enum.find(connection["models"] || [], &(&1["id"] == role["model_id"]))
    observation = agent.codex
    probe = if(observation["command_id"], do: Repo.get(Command, observation["command_id"]))
    identity = if(probe, do: Foundation.executable_identity(probe.payload))

    Map.merge(Map.take(role, ~w(id name instructions)), %{
      "agent_id" => role["agent"],
      "agent_name" => Map.get(agent, :name),
      "kind" => agent.kind,
      "model_id" => role["model_id"],
      "model" => role["model"],
      "effort" => if(model, do: model["default_effort"]),
      "identity" => identity,
      "version" => observation["version"],
      "connection_command_id" => connection["command_id"],
      "fetched_at" => connection["fetched_at"],
      "status" => binding_status(role, agent, probe, model)
    })
  end

  defp binding_status(_, %{id: nil}, _, _), do: "agent_unassigned"
  defp binding_status(%{"model_id" => ""}, _, _, _), do: "model_unassigned"

  defp binding_status(role, agent, probe, model) do
    cond do
      agent.kind not in ~w(codex cursor) ->
        "unsupported_provider"

      not valid_probe?(probe, agent) ->
        "version_required"

      runtime_status(agent) != "ready" ->
        runtime_status(agent)

      not connected?(agent) ->
        "connection_required"

      not Foundation.reusable_catalog?(agent.connection) ->
        "catalog_stale"

      not valid_model?(role, model, agent.kind) ->
        "model_unavailable"

      true ->
        "ready"
    end
  end

  defp runtime_status(%{kind: "cursor", codex: observation}),
    do: if(observation["version"] == Cursor.task_version(), do: "ready", else: "version_required")

  defp runtime_status(%{kind: "codex", codex: observation}),
    do:
      if(Codex.task_version?(observation["version"]),
        do: "ready",
        else: "task_runtime_version_required"
      )

  defp valid_probe?(%Command{state: "completed"} = probe, agent),
    do:
      probe.kind == "probe_#{agent.kind}" and agent.codex["status"] == "supported" and
        Foundation.agent_id(probe.payload) == agent.id and
        agent.connection["identity"] == Foundation.executable_identity(probe.payload)

  defp valid_probe?(_, _), do: false

  defp connected?(agent),
    do:
      agent.connection["status"] == "checked" and
        agent.connection["authorization"] ==
          if(agent.kind == "cursor", do: "cursor", else: "chatgpt")

  defp valid_model?(_, nil, _), do: false

  defp valid_model?(role, model, "cursor"), do: role["model"] == model["model"]

  defp valid_model?(role, model, "codex"),
    do: role["model"] == model["model"] and model["default_effort"] in (model["efforts"] || [])
end
