defmodule Cuckoding.Battles.Snapshot do
  @moduledoc false
  alias Cuckoding.{
    Agents,
    Codex,
    Command,
    Foundation,
    ProjectChecks,
    Repo,
    Tabulae,
    TeamAssignments
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
    "turns" => 200,
    "wall_seconds" => 7200,
    "stage_seconds" => 900
  }

  # This function reads SQLite only. Native admission revalidates every recorded identity.
  def build(arena_id, tabula_id) do
    arena = Tabulae.arena(arena_id) || Repo.rollback(:scope_missing)
    board = Tabulae.get(arena.id, tabula_id) || Repo.rollback(:scope_missing)
    team = TeamAssignments.assigned(board)
    roles = Enum.map(team.definition["roles"], &role_binding/1)
    tasks = Enum.map(Tabulae.tasks(board.id), &task/1)
    checks = ProjectChecks.current(arena.id)
    {ordered, graph_valid?} = order(tasks, [])

    blockers =
      []
      |> block(tasks == [], "no_tasks")
      |> block(length(tasks) > @limits["tasks"], "task_limit")
      |> block(Enum.any?(tasks, &incomplete?/1), "incomplete_task")
      |> block(not graph_valid?, "invalid_dependencies")
      |> block(
        columns(board) != @columns or Enum.map(roles, & &1["id"]) != @roles,
        "unsupported_columns"
      )
      |> block(checks.definition["checks"] == [], "checks_required")
      |> block(check_limits?(checks.definition["checks"]), "check_timeout_limit")
      |> block(
        Enum.any?(
          roles,
          &(&1["id"] == "implementor" and &1["version"] != Codex.isolation_version())
        ),
        "check_runtime_version_required"
      )
      |> Kernel.++(roles |> Enum.map(& &1["status"]) |> Enum.reject(&(&1 == "ready")))
      |> Enum.uniq()

    snapshot = %{
      "version" => "arena-loop-v1",
      "arena_id" => arena.id,
      "tabula_id" => board.id,
      "source" =>
        Map.new(~w(path device inode), &{&1, Map.fetch!(arena, String.to_existing_atom(&1))}),
      "team_revision" => team.id,
      "team" => roles,
      "tasks" => if(graph_valid?, do: ordered, else: tasks),
      "check_revision" => checks.revision,
      "checks" => checks.definition["checks"],
      "limits" => @limits
    }

    %{
      snapshot: snapshot,
      fingerprint: digest(snapshot),
      blockers: blockers,
      tasks: snapshot["tasks"],
      team: roles,
      checks: snapshot["checks"],
      limits: @limits
    }
  end

  def digest(value), do: ProjectChecks.digest(value)

  defp block(reasons, true, reason), do: reasons ++ [reason]
  defp block(reasons, false, _), do: reasons
  defp columns(board), do: Enum.map(board.definition["columns"] || [], &{&1["key"], &1["role"]})

  defp check_limits?(checks),
    do:
      Enum.any?(checks, &(&1["timeout_seconds"] > 300)) or
        Enum.sum(Enum.map(checks, & &1["timeout_seconds"])) > 600

  defp task(task) do
    Tabulae.content(task)
    |> Map.merge(%{
      "id" => task.id,
      "revision" => task.revision,
      "criteria_sha256" => digest(task.criteria)
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

  defp binding_status(role, agent, probe, model) do
    cond do
      is_nil(agent.id) or role["model_id"] == "" -> "agent_unassigned"
      agent.kind != "codex" -> "unsupported_provider"
      not valid_probe?(probe, agent) -> "version_required"
      not connected?(agent.connection) -> "connection_required"
      Foundation.catalog_status(agent.connection) != "fresh" -> "catalog_stale"
      not valid_model?(role, model) -> "model_unavailable"
      true -> "ready"
    end
  end

  defp valid_probe?(%Command{kind: "probe_codex", state: "completed"} = probe, agent),
    do:
      agent.codex["status"] == "supported" and Foundation.agent_id(probe.payload) == agent.id and
        agent.connection["identity"] == Foundation.executable_identity(probe.payload)

  defp valid_probe?(_, _), do: false

  defp connected?(connection),
    do: connection["status"] == "checked" and connection["authorization"] == "chatgpt"

  defp valid_model?(_, nil), do: false

  defp valid_model?(role, model),
    do: role["model"] == model["model"] and model["default_effort"] in (model["efforts"] || [])
end
