defmodule CuckodingWeb.CandidateRecoveryLiveTest do
  use CuckodingWeb.ConnCase
  import Phoenix.LiveViewTest
  import Cuckoding.BattleFixtures
  alias Cuckoding.{Battles, Repo}
  alias Cuckoding.Battles.Attempt

  test "Inspect shows retained checkpoint observations and explicit Resume without exposing claims",
       %{conn: conn} do
    %{board: board} = fixture()
    battle = start(board)
    capture = capturing(battle)
    {:ok, _} = Battles.recover()
    interrupted = Repo.get!(Attempt, capture.id)
    {:ok, view, _} = conn |> sign_in() |> live("/arenas/#{board.arena_id}/tabulae/#{board.id}")
    assert has_element?(view, "#battle-candidate-inspecting", "No capture, edit or agent turn")
    refute has_element?(view, "#arena-start:not([disabled])")
    preparation = capture.request["task_context"]["preparation"]

    native = %{
      "status" => "candidate_captured",
      "key" => capture.id,
      "worktree_key" => preparation["key"],
      "base" => preparation["head"],
      "candidate" => String.duplicate("c", 40),
      "tree" => String.duplicate("d", 40),
      "manifest_sha256" => String.duplicate("e", 64)
    }

    receipt =
      result(capture, %{"candidate_sha" => native["candidate"], "native_candidate" => native})

    {:ok, paused} = Battles.reconcile_recovery(interrupted, receipt)
    assert paused.state == "paused"
    refute has_element?(view, "#battle-candidate-inspecting")
    assert has_element?(view, "#battle-candidate-reconciliation-#{capture.id}", "Verified")
    assert has_element?(view, "#battle-candidate-reconciliation-#{capture.id}", "Observed")
    assert has_element?(view, "#battle-candidate-reconciliation-#{capture.id}", "Every member")
    html = render(view)
    assert html =~ "Resume"
    refute html =~ capture.claim_token
    assert Repo.get!(Attempt, capture.id) == interrupted
  end

  defp capturing(battle) do
    {:ok, attempt} = Battles.claim_next(battle.id)

    if attempt.stage == "capture" do
      attempt
    else
      {:ok, next} = Battles.finish(attempt.id, attempt.claim_token, result(attempt))
      capturing(next)
    end
  end
end
