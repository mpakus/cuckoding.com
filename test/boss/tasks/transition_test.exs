defmodule Boss.Tasks.TransitionTest do
  use ExUnit.Case, async: true
  alias Boss.Tasks.Transition

  @workflow ~w(new planning ready implementing testing reviewing approved ready_to_merge integrating)
  @active ~w(planning implementing testing reviewing integrating)
  @attention ~w(blocked needs_input failed interrupted cancelled)
  @forward [
    {"new", "start_planning", :runner},
    {"planning", "finish_planning", :runner},
    {"ready", "start_implementation", :runner},
    {"implementing", "finish_implementation", :runner},
    {"testing", "checks_passed", :checks},
    {"reviewing", "approve_review", :review},
    {"reviewing", "request_changes", :review},
    {"reviewing", "revise_spec", :review},
    {"approved", "queue_merge", :integration},
    {"approved", "start_integration", :integration},
    {"ready_to_merge", "start_integration", :integration},
    {"integrating", "finish_integration", :integration}
  ]

  test "every producer-dependent forward action fails closed" do
    for {state, action, producer} <- @forward do
      assert {:error, {:gate_unavailable, ^producer}} = Transition.apply(task(state), action, nil)

      forged =
        Map.merge(task(state), %{verified: true, approved: true, evidence: %{passed: true}})

      assert {:error, {:gate_unavailable, ^producer}} = Transition.apply(forged, action, nil)
    end
  end

  test "forward actions reject every other source state" do
    for state <- @workflow ++ @attention ++ ["done"],
        action <- @forward |> Enum.map(&elem(&1, 1)) |> Enum.uniq(),
        not Enum.any?(@forward, fn {from, allowed, _} -> from == state and allowed == action end) do
      assert {:error, :invalid_transition} = Transition.apply(task(state, "new"), action, nil)
    end
  end

  test "attention actions preserve workflow states as recovery targets and exact reasons" do
    for state <- @workflow,
        {action, destination} <- [
          {"block", "blocked"},
          {"needs_input", "needs_input"},
          {"cancel", "cancelled"}
        ] do
      original = Map.merge(task(state), %{spec_revision_id: 42, title: "Pinned"})
      reason = "  Waiting for input\nfrom the owner.  "

      assert {:ok,
              %{state: ^destination, recovery_state: ^state, attention_reason: ^reason} = attrs} =
               Transition.apply(original, action, reason)

      assert Map.keys(attrs) |> Enum.sort() == [:attention_reason, :recovery_state, :state]
      assert original.spec_revision_id == 42
      assert original.title == "Pinned"
    end
  end

  test "exception switches retain their original recovery target" do
    for state <- ~w(blocked needs_input failed interrupted),
        {action, destination} <- [
          {"block", "blocked"},
          {"needs_input", "needs_input"},
          {"cancel", "cancelled"}
        ],
        destination != state,
        recovery <- @workflow do
      assert {:ok,
              %{state: ^destination, recovery_state: ^recovery, attention_reason: "New reason"}} =
               Transition.apply(task(state, recovery), action, "New reason")
    end
  end

  test "only active phases may fail or be interrupted" do
    for state <- @workflow ++ @attention ++ ["done"],
        {action, destination} <- [{"fail", "failed"}, {"interrupt", "interrupted"}] do
      if state in @active do
        assert {:ok, %{state: ^destination, recovery_state: ^state, attention_reason: "Stopped"}} =
                 Transition.apply(task(state), action, "Stopped")
      else
        assert {:error, :invalid_transition} =
                 Transition.apply(task(state, "new"), action, "Stopped")
      end
    end
  end

  test "resume and retry are restricted to their explicit exceptional states" do
    for state <- @workflow ++ @attention ++ ["done"], action <- ["resume", "retry"] do
      allowed =
        if action == "resume",
          do: state in ~w(blocked needs_input),
          else: state in ~w(failed interrupted cancelled)

      if allowed do
        assert {:ok, %{state: "new", recovery_state: nil, attention_reason: nil}} =
                 Transition.apply(task(state, "new"), action, nil)
      else
        assert {:error, :invalid_transition} = Transition.apply(task(state, "new"), action, nil)
      end
    end
  end

  test "recovery to every execution stage remains gated" do
    for {state, action} <- [
          {"blocked", "resume"},
          {"needs_input", "resume"},
          {"failed", "retry"},
          {"interrupted", "retry"},
          {"cancelled", "retry"}
        ],
        {recovery, producer} <- [
          {"planning", :runner},
          {"ready", :runner},
          {"implementing", :runner},
          {"testing", :checks},
          {"reviewing", :review},
          {"approved", :review},
          {"ready_to_merge", :integration},
          {"integrating", :integration}
        ] do
      assert {:error, {:gate_unavailable, ^producer}} =
               Transition.apply(task(state, recovery), action, nil)
    end
  end

  test "invalid recovery targets cannot reset or traverse attention chains" do
    for recovery <- [
          nil,
          "done",
          "unknown",
          :new,
          "blocked",
          "needs_input",
          "failed",
          "interrupted",
          "cancelled"
        ],
        {state, action, reason} <- [
          {"blocked", "resume", nil},
          {"cancelled", "retry", nil},
          {"failed", "block", "Hold"},
          {"needs_input", "cancel", "Stop"}
        ] do
      assert {:error, :invalid_recovery_state} =
               Transition.apply(task(state, recovery), action, reason)
    end

    {:ok, blocked} = Transition.apply(task("implementing"), "block", "Hold")
    {:ok, input} = Transition.apply(blocked, "needs_input", "Explain")
    {:ok, cancelled} = Transition.apply(input, "cancel", "Stop")
    assert cancelled.recovery_state == "implementing"
    assert {:error, {:gate_unavailable, :runner}} = Transition.apply(cancelled, "retry", nil)
  end

  test "done is immutable and cancellation has only retry" do
    actions =
      Enum.map(@forward, &elem(&1, 1)) ++ ~w(block needs_input cancel fail interrupt resume retry)

    for action <- actions do
      reason = if action in ~w(block needs_input cancel fail interrupt), do: "Reason", else: nil
      assert {:error, :invalid_transition} = Transition.apply(task("done"), action, reason)
    end

    for action <- ~w(block needs_input cancel fail interrupt) do
      assert {:error, :invalid_transition} =
               Transition.apply(task("cancelled", "new"), action, "Reason")
    end

    for {state, action} <- [{"blocked", "block"}, {"needs_input", "needs_input"}] do
      assert {:error, :invalid_transition} =
               Transition.apply(task(state, "new"), action, "Reason")
    end
  end

  test "exception actions require bounded nonblank UTF-8 reasons without NUL" do
    for {state, action} <- [
          {"new", "block"},
          {"new", "needs_input"},
          {"new", "cancel"},
          {"planning", "fail"},
          {"planning", "interrupt"}
        ],
        reason <- [
          nil,
          "",
          " \n\t",
          <<255>>,
          "bad\0reason",
          :reason,
          %{},
          String.duplicate("я", 501)
        ] do
      assert {:error, :invalid_reason} = Transition.apply(task(state), action, reason)
    end

    reason = String.duplicate("я", 500)
    assert {:ok, %{attention_reason: ^reason}} = Transition.apply(task("new"), "block", reason)
  end

  test "recovery and forward commands reject supplied reasons" do
    commands =
      Enum.map(@forward, fn {state, action, _} -> {state, action} end) ++
        [{"blocked", "resume"}, {"cancelled", "retry"}]

    for {state, action} <- commands, reason <- ["", "Approved by me", %{}, 1] do
      assert {:error, :invalid_reason} = Transition.apply(task(state, "new"), action, reason)
    end
  end

  test "unknown states, malformed tasks and non-string actions fail closed" do
    for invalid <- [
          nil,
          %{},
          %{state: "new"},
          %{state: "unknown", recovery_state: nil, attention_reason: nil},
          task(:new)
        ] do
      assert {:error, :invalid_task} = Transition.apply(invalid, "block", "Reason")
    end

    for action <- [
          nil,
          :block,
          %{"action" => "block"},
          "",
          "approved",
          "set_state",
          "new",
          "resume_to_new",
          "BLOCK"
        ] do
      assert {:error, :invalid_action} = Transition.apply(task("new"), action, "Reason")
    end
  end

  test "only done satisfies a dependency" do
    for state <- @workflow ++ @attention do
      refute Transition.dependency_satisfied?(task(state))
    end

    assert Transition.dependency_satisfied?(task("done"))
    refute Transition.dependency_satisfied?(nil)
    refute Transition.dependency_satisfied?(%{state: :done})
  end

  defp task(state, recovery \\ nil),
    do: %{state: state, recovery_state: recovery, attention_reason: nil}
end
