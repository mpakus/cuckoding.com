defmodule Cuckoding.BattlePreviewTest do
  use Cuckoding.DataCase
  import Cuckoding.SpecificationFixtures

  alias Cuckoding.{
    ArenaGit,
    BattlePreview,
    Command,
    Event,
    Foundation,
    ProjectChecks,
    Specifications,
    Tabulae,
    Team,
    TeamAssignments
  }

  setup do: specification_fixture()

  defp preview(board, now \\ DateTime.utc_now()) do
    {:ok, preview} = BattlePreview.inspect(board.arena_id, board.id, now)
    preview
  end

  defp accept(board, task, revision \\ 1) do
    {:ok, _} = request_spec(board, task, revision)
    {:ok, claim} = Foundation.claim()
    {:ok, done} = Foundation.finish(claim, Specifications.execute(claim))
    done
  end

  test "scoped read includes all drafts and exact checks without commands or events", ctx do
    %{board: b, task: task, attrs: attrs} = ctx
    other = Cuckoding.DataCase.arena_fixture()
    {:ok, other_board} = Tabulae.create(Ecto.UUID.generate(), other.id, "Other")

    {:ok, _} =
      Tabulae.save(
        Ecto.UUID.generate(),
        b.arena_id,
        b.id,
        task,
        1,
        Map.put(attrs, "column", "todo")
      )

    empty = preview(b)
    assert empty.git.status == :not_inspected
    assert empty.checks.revision == 0
    assert empty.checks.definition["checks"] == []
    assert hd(empty.tasks).spec.status == :unaccepted

    check = %{
      "id" => Ecto.UUID.generate(),
      "name" => "Tests",
      "executable" => "mix",
      "arguments" => ["test", "a b", "$(unchanged)"],
      "directory" => ".",
      "timeout_seconds" => 120
    }

    {:ok, saved} = ProjectChecks.save(Ecto.UUID.generate(), b.arena_id, 0, [check], true)
    before = {Repo.all(Command), Repo.all(Event)}
    report = preview(b)
    assert report.execution == :unavailable
    assert report.team_revision == b.team_revision_id
    assert Enum.all?(report.roles, &(&1.status == :unassigned))
    assert report.checks == saved
    assert Enum.map(report.tasks, & &1.id) == [task]
    assert {:error, :scope_missing} = BattlePreview.inspect(other.id, b.id)
    assert {:error, :scope_missing} = BattlePreview.inspect(b.arena_id, other_board.id)
    assert {:error, :scope_missing} = BattlePreview.inspect("bad", b.id)
    assert {:error, :scope_missing} = BattlePreview.inspect(b.arena_id, %{})
    assert {Repo.all(Command), Repo.all(Event)} == before
    refute Foundation.pending?()
  end

  test "acceptance is bound to current draft, prerequisites and retained bytes", ctx do
    %{board: b, task: task, attrs: attrs, root: root} = ctx
    dep = Ecto.UUID.generate()

    {:ok, _} =
      Tabulae.save(
        Ecto.UUID.generate(),
        b.arena_id,
        b.id,
        dep,
        0,
        Map.put(attrs, "title", "Prerequisite")
      )

    dep_spec = accept(b, dep)
    attrs = Map.put(attrs, "depends_on", [dep])
    {:ok, _} = Tabulae.save(Ecto.UUID.generate(), b.arena_id, b.id, task, 1, attrs)
    spec = accept(b, task, 2)
    report = preview(b)
    assert Enum.all?(report.tasks, &(&1.spec.status == :accepted))
    assert Enum.find(report.tasks, &(&1.id == task)).spec.id == spec.id
    File.write!(Path.join(root, "specifications/#{dep_spec.id}.md"), "edited")
    report = preview(b)
    assert Enum.find(report.tasks, &(&1.id == dep)).spec.status == :artifact_unavailable

    {:ok, _} =
      Tabulae.save(
        Ecto.UUID.generate(),
        b.arena_id,
        b.id,
        dep,
        2,
        Map.put(attrs, "depends_on", [])
      )

    report = preview(b)
    assert Enum.find(report.tasks, &(&1.id == task)).spec.status == :outdated
    assert Enum.find(report.tasks, &(&1.id == dep)).spec.status == :unaccepted
    assert {:ok, _} = Specifications.read(spec.id)
  end

  test "latest Git observation must be completed, validated and less than five minutes old", %{
    board: b
  } do
    for {receipt, expected} <- [
          {%{"status" => "missing"}, :missing},
          {%{"status" => "unborn"}, :no_commit},
          {%{"status" => "existing", "head" => "invalid"}, :failed},
          {%{"status" => "existing", "head" => String.duplicate("a", 40)}, :observed}
        ] do
      {:ok, _} = ArenaGit.request(Ecto.UUID.generate(), b.arena_id, "inspect")
      assert preview(b).git.status == :busy
      {:ok, claim} = Foundation.claim()
      {:ok, done} = Foundation.finish(claim, receipt)
      report = preview(b, done.updated_at)
      assert report.git.status == expected
      assert report.git.id == done.id
    end

    current = ArenaGit.latest(b.arena_id)
    assert preview(b, DateTime.add(current.updated_at, 299)).git.status == :observed
    assert preview(b, DateTime.add(current.updated_at, 300)).git.status == :expired
    assert preview(b, DateTime.add(current.updated_at, -1)).git.status == :expired
    {:ok, _} = ArenaGit.request(Ecto.UUID.generate(), b.arena_id, "inspect")
    assert preview(b).busy
    assert preview(b).git.status == :busy
    assert preview(b).git.head == nil
  end

  test "team adoption and catalog drift never silently replace saved bindings" do
    %{board: b} = Cuckoding.PlanningFixtures.planning_fixture()
    original = preview(b)
    assert hd(original.roles).status == :untested
    team = Team.current()

    roles =
      Enum.map(
        Team.editable(team),
        &Map.merge(&1, %{"agent" => "codex", "model_id" => "test-id"})
      )

    {:ok, next} = Team.save(Ecto.UUID.generate(), team.id, roles)
    assert preview(b).team_revision == original.team_revision

    {:ok, _} =
      TeamAssignments.adopt(
        Ecto.UUID.generate(),
        b.arena_id,
        b.id,
        original.team_revision,
        next.id,
        true
      )

    assert Enum.all?(preview(b).roles, &(&1.status == :untested))
    workspace = Foundation.workspace()
    old = workspace.connection
    stale = Map.put(old, "fetched_at", "2000-01-01T00:00:00Z")
    Repo.update!(Ecto.Changeset.change(workspace, connection: stale))
    assert Enum.all?(preview(b).roles, &(&1.status == :catalog_stale))
    changed = Map.update!(old, "models", fn [model] -> [Map.put(model, "model", "different")] end)
    Repo.update!(Ecto.Changeset.change(workspace, connection: changed))
    report = preview(b)
    assert Enum.all?(report.roles, &(&1.status == :model_changed))
    assert Enum.all?(report.roles, &(&1.definition["model"] == "test-model"))
  end
end
