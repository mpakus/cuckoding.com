defmodule Cuckoding.PlannedChecksTest do
  use Cuckoding.DataCase
  import Cuckoding.PlanningFixtures
  alias Cuckoding.{DraftTaskRevision, Foundation, Planning, Repo, Tabulae}
  setup do: planning_fixture()

  defp checks, do: [%{"profile" => "npm-test", "directory" => "web", "timeout_seconds" => 60}]

  test "v4 planning imports profiles once and omitted legacy edits preserve them", %{board: board} do
    setup = Planning.setup(board)
    assert setup.payload["contract"] == "brief-plan-v4"

    {:ok, command} =
      Planning.request(
        Ecto.UUID.generate(),
        board.arena_id,
        board.id,
        "Build it",
        setup.token,
        true
      )

    {:ok, claim} = Foundation.claim()
    receipt = planning_receipt(command.id)

    receipt =
      update_in(
        receipt["proposal"]["tasks"],
        &Enum.map(&1, fn task -> Map.put(task, "verification", checks()) end)
      )

    {:ok, %{state: "completed"}} = Foundation.finish(claim, receipt)
    [task] = Tabulae.tasks(board.id)
    assert task.verification == checks()
    original = Repo.get_by!(DraftTaskRevision, task_id: task.id, revision: 1)
    assert original.content["verification"] == checks()

    attrs =
      Tabulae.content(task) |> Map.delete("verification") |> Map.put("criteria", "New criteria")

    assert {:ok, saved} =
             Tabulae.save(Ecto.UUID.generate(), board.arena_id, board.id, task.id, 1, attrs)

    assert saved.content["verification"] == checks()
    assert Repo.get!(DraftTaskRevision, original.id) == original

    assert {:ok, cleared} =
             Tabulae.save(
               Ecto.UUID.generate(),
               board.arena_id,
               board.id,
               task.id,
               2,
               Map.put(attrs, "verification", [])
             )

    assert cleared.content["verification"] == []
    assert length(Tabulae.tasks(board.id)) == 1
  end

  test "v4 rejects downgrade, arbitrary commands and foreign profile fields before import", %{
    board: board
  } do
    for invalid <- [:missing, :unknown, :arguments] do
      setup = Planning.setup(board)

      {:ok, command} =
        Planning.request(
          Ecto.UUID.generate(),
          board.arena_id,
          board.id,
          "Plan",
          setup.token,
          true
        )

      {:ok, claim} = Foundation.claim()
      receipt = planning_receipt(command.id)

      receipt =
        update_in(receipt["proposal"]["tasks"], fn [task] ->
          [
            case invalid do
              :missing ->
                Map.delete(task, "verification")

              :unknown ->
                Map.put(task, "verification", [Map.put(hd(checks()), "profile", "shell")])

              :arguments ->
                Map.put(task, "verification", [Map.put(hd(checks()), "arguments", ["install"])])
            end
          ]
        end)

      assert {:ok, %{state: "failed"}} = Foundation.finish(claim, receipt)
      assert Tabulae.tasks(board.id) == []
    end
  end
end
