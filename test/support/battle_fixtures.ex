defmodule Cuckoding.BattleFixtures do
  @moduledoc false
  import ExUnit.Assertions
  alias Cuckoding.Battles.{Attempt, Battle, Snapshot, Task}

  alias Cuckoding.{
    Battles,
    Codex,
    Foundation,
    ProjectChecks,
    Repo,
    Tabulae,
    Team,
    TeamAssignments
  }

  def fixture do
    %{board: board} = Cuckoding.PlanningFixtures.planning_fixture()
    workspace = Foundation.workspace()

    Repo.update!(
      Ecto.Changeset.change(workspace,
        codex: Map.put(workspace.codex, "version", Codex.isolation_version())
      )
    )

    team = Team.current()

    roles =
      Enum.map(
        Team.editable(team),
        &Map.merge(&1, %{"agent" => "codex", "model_id" => "test-id"})
      )

    {:ok, team} = Team.save(Ecto.UUID.generate(), team.id, roles)

    {:ok, _} =
      TeamAssignments.adopt(
        Ecto.UUID.generate(),
        board.arena_id,
        board.id,
        board.team_revision_id,
        team.id,
        true
      )

    check = %{
      "id" => Ecto.UUID.generate(),
      "name" => "Tests",
      "executable" => "true",
      "arguments" => ["test"],
      "directory" => ".",
      "timeout_seconds" => 120
    }

    {:ok, _} = ProjectChecks.save(Ecto.UUID.generate(), board.arena_id, 0, [check], true)
    first = save_task(board, "First", [])
    second = save_task(board, "Second", [first.id])
    %{board: board, first: first, second: second, check: check}
  end

  def save_task(board, title, dependencies) do
    {:ok, _} =
      Tabulae.save(Ecto.UUID.generate(), board.arena_id, board.id, Ecto.UUID.generate(), 0, %{
        "title" => title,
        "description" => "Implement #{title}",
        "criteria" => "Retain all acceptance criteria #{title}",
        "column" => "specs",
        "depends_on" => dependencies
      })

    Enum.find(Tabulae.tasks(board.id), &(&1.title == title))
  end

  def start(board) do
    {:ok, preview} = Battles.preview(board.arena_id, board.id)
    assert preview.blockers == []

    {:ok, battle} =
      Battles.start(Ecto.UUID.generate(), board.arena_id, board.id, preview.fingerprint, true)

    battle
  end

  def start_legacy(board, omitted) do
    {:ok, preview} = Battles.preview(board.arena_id, board.id)
    assert preview.blockers == []
    snapshot = Map.drop(preview.snapshot, omitted)

    battle =
      Repo.insert!(%Battle{
        id: Ecto.UUID.generate(),
        arena_id: board.arena_id,
        tabula_id: board.id,
        snapshot: snapshot,
        fingerprint: Snapshot.digest(snapshot),
        state: "running",
        stage: "admission",
        deadline_at: DateTime.add(DateTime.utc_now(), 7200)
      })

    for {task, position} <- Enum.with_index(snapshot["tasks"]) do
      Repo.insert!(%Task{
        id: Ecto.UUID.generate(),
        battle_id: battle.id,
        task_id: task["id"],
        position: position,
        snapshot: task
      })
    end

    battle
  end

  def result(attempt, override \\ %{})

  def result(%Attempt{stage: "combine"} = attempt, override) do
    payload = combined_result(attempt)

    Map.take(attempt.request, ~w(battle_id request_id task_id stage criteria_sha256))
    |> Map.merge(payload)
    |> Map.put("cleanup_verified", true)
    |> Map.merge(override)
  end

  def result(attempt, override) do
    envelope = Map.take(attempt.request, ~w(battle_id request_id task_id stage criteria_sha256))

    candidate =
      attempt.request["task_context"]["candidate_sha"] || attempt.request["context"]["head"]

    payload =
      case attempt.stage do
        "admission" ->
          %{
            "status" => "admitted",
            "head" => String.duplicate("a", 40),
            "native_battle" => %{"reference" => "refs/ccoding/battles/#{attempt.battle_id}"},
            "resolved_checks" => attempt.request["snapshot"]["checks"]
          }

        "prepare_worktree" ->
          %{
            "status" => "prepared",
            "preparation" => %{"key" => attempt.id, "head" => attempt.request["context"]["head"]}
          }

        "capture" ->
          %{
            "status" => "captured",
            "candidate_sha" => Base.encode16(:crypto.hash(:sha, attempt.id), case: :lower),
            "native_candidate" => %{"key" => attempt.id}
          }

        stage when stage in ~w(checks final_checks) ->
          %{
            "status" => "passed",
            "candidate_sha" => candidate,
            "checks" =>
              Enum.map(
                attempt.request["snapshot"]["checks"],
                &%{"id" => &1["id"], "status" => "passed", "exit_code" => 0}
              )
          }

        "integrate" ->
          %{
            "status" => "integrated",
            "candidate_sha" => candidate,
            "head" => candidate,
            "native_battle" => %{"head" => candidate}
          }

        _ ->
          %{
            "status" => "completed",
            "candidate_sha" => candidate,
            "provider" => %{
              "status" => "task_finished",
              "request_id" => attempt.id,
              "grant" => "host-task-tools-v1",
              "access" => if(attempt.stage == "implementor", do: "write", else: "read"),
              "requested_model" => "test-model",
              "observed_model" => "test-model",
              "effort" => "low",
              "thread_id" => Ecto.UUID.generate(),
              "turn_id" => Ecto.UUID.generate(),
              "report" => %{"summary" => "Public evidence", "outcome" => "completed"},
              "tools" => [
                %{
                  "call_id" => Ecto.UUID.generate(),
                  "tool" => "read_file",
                  "status" => "completed",
                  "path" => "README.md",
                  "sha256" => String.duplicate("a", 64)
                }
              ]
            }
          }
      end

    envelope |> Map.merge(payload) |> Map.put("cleanup_verified", true) |> Map.merge(override)
  end

  defp combined_result(attempt) do
    context = attempt.request["task_context"]
    head = Base.encode16(:crypto.hash(:sha, attempt.id), case: :lower)

    %{
      "status" => "combined",
      "candidate_sha" => head,
      "native_candidate" => %{
        "status" => "candidate_combined",
        "key" => attempt.id,
        "battle_key" => attempt.battle_id,
        "worktree_key" => context["preparation"]["key"],
        "task_candidate_key" => context["native_candidate"]["key"],
        "base" => attempt.request["context"]["head"],
        "task_base" => context["preparation"]["head"],
        "candidate" => head,
        "tree" => String.duplicate("a", 40),
        "manifest_sha256" => String.duplicate("b", 64)
      }
    }
  end
end
