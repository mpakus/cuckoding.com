defmodule Cuckoding.BattlePreview do
  @moduledoc "Read-only preparation evidence. Never a battle snapshot or launch authority."
  import Ecto.Query

  alias Cuckoding.{
    ArenaGit,
    Command,
    DraftTaskRevision,
    Foundation,
    LocalGit,
    ProjectChecks,
    Repo,
    Specifications,
    Tabulae,
    Team,
    TeamAssignments
  }

  def inspect(arena_id, tabula_id, now \\ DateTime.utc_now()) do
    Repo.transaction(fn ->
      arena = Tabulae.arena(arena_id) || Repo.rollback(:scope_missing)
      board = Tabulae.get(arena.id, tabula_id) || Repo.rollback(:scope_missing)
      team = TeamAssignments.assigned(board)
      catalog = Team.catalog()
      tasks = Enum.map(Tabulae.tasks(board.id), &task/1)

      %{
        arena: arena,
        board: board,
        checked_at: now,
        execution: :unavailable,
        busy: Foundation.pending?(),
        team_revision: team.id,
        roles: Enum.map(team.definition["roles"], &role(&1, catalog)),
        tasks: tasks,
        checks: ProjectChecks.current(arena.id),
        git: git(ArenaGit.latest(arena.id), now)
      }
    end)
  end

  defp role(role, catalog) do
    %{
      definition: role,
      status: Team.binding_status(role, catalog),
      required: Team.required?(role["id"])
    }
  end

  defp task(task) do
    # The current revision's command identifies acceptance directly; UI history is truncated.
    acceptance =
      Repo.one(
        from c in Command,
          join: r in DraftTaskRevision,
          on: r.command_id == c.id,
          where:
            r.task_id == ^task.id and r.revision == ^task.revision and c.kind == "accept_spec" and
              c.state == "completed" and c.result == "accepted"
      )

    %{
      id: task.id,
      title: task.title,
      revision: task.revision,
      column: task.column,
      depends_on: task.depends_on,
      spec: spec(acceptance)
    }
  end

  defp spec(nil), do: %{status: :unaccepted, id: nil, sha256: nil}

  defp spec(command) do
    status =
      cond do
        not Specifications.current?(command) -> :outdated
        not match?({:ok, _}, Specifications.read(command.id)) -> :artifact_unavailable
        true -> :accepted
      end

    %{status: status, id: command.id, sha256: command.payload["sha256"]}
  end

  defp git(nil, _), do: %{status: :not_inspected, id: nil, at: nil, head: nil, result: nil}

  defp git(command, now) do
    observation = LocalGit.normalize(command.payload["observation"])

    status =
      cond do
        command.state in ~w(pending running cancelling) -> :busy
        command.state != "completed" -> :failed
        DateTime.diff(now, command.updated_at) not in 0..299 -> :expired
        observation["status"] in ~w(existing committed) -> :observed
        observation["status"] == "missing" -> :missing
        observation["status"] in ~w(unborn initialized previewed) -> :no_commit
        true -> :failed
      end

    %{
      status: status,
      id: command.id,
      at: command.updated_at,
      head: observation["head"],
      result: command.result
    }
  end
end
