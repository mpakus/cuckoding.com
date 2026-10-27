defmodule BossWeb.DeliveryPanelTest do
  use ExUnit.Case, async: true
  import Phoenix.LiveViewTest
  alias BossWeb.DeliveryPanel

  test "explicit workflow start explains trusted checks, retries and account usage" do
    html = panel([])
    assert html =~ "Start workflow"
    assert html =~ "maximum of three implementation/check/review cycles"
    assert html =~ "local Codex account"
    assert html =~ "may incur charges for multiple runs"
    assert html =~ "without shell expansion"
    assert html =~ "Keep secrets out of arguments and output"
    assert html =~ ~s(name="command_id" value="start-request")
    assert html =~ ~s(for="delivery-reviewer")
    assert html =~ ~s(value="codex" selected)
    assert html =~ "Codex plans and implements"
  end

  test "active workflow exposes Stop and its saved command and candidate" do
    delivery = delivery("testing")
    html = panel([delivery], start_available: false)
    assert html =~ "Checking candidate"
    assert html =~ "Stop workflow"
    assert html =~ "Cycle 2 of 3"
    assert html =~ "mix"
    assert html =~ String.duplicate("a", 40)
    refute html =~ "Integrate approved result"
  end

  test "ready is explicit integration, includes target contract, and is not Done" do
    html = panel([delivery("ready_to_merge")])
    assert html =~ "Ready to integrate"
    assert html =~ "Integrate approved result"
    assert html =~ "only fast-forwards the unchanged target"
    assert html =~ "must not be checked out"
    assert html =~ "Done requires successful checks after publication"
    refute html =~ "Done — integrated and checks passed"
    refute html =~ "Stop workflow"
  end

  test "validated plan and review text are escaped and stages stay separate" do
    html = panel([delivery("ready_to_merge")])
    assert html =~ "Saved plan and criteria"
    assert html =~ "Keep source immutable"
    assert html =~ "Review: Approved"
    assert html =~ "&lt;script&gt;not executable&lt;/script&gt;"
    refute html =~ "<script>"
    assert html =~ "Saved stages"
  end

  test "Ready Claude history explains both roles even when a fresh request defaults to Codex" do
    saved = %{delivery("ready_to_merge") | reviewer: "claude"}

    html =
      panel([saved],
        details: %{
          task: %{state: "ready_to_merge"},
          pinned_revision: %{id: 7, number: 1},
          revisions: [%{id: 7, number: 1}]
        }
      )

    assert html =~ "Reviewer: Claude"
    assert html =~ "Codex account for planning and implementation"
    assert html =~ "selected reviewer's account for review"
    refute html =~ "Uses your local Codex account and may incur charges"
    refute html =~ ~s(id="delivery-form")
  end

  test "unknown request keeps the command read-only and offers an identical retry" do
    html =
      panel([],
        request: %{id: "start-request", text: "mix test", reviewer: "claude", locked: true},
        uncertain: true
      )

    assert html =~ "Retry workflow start"
    assert html =~ "readonly"
    assert html =~ "workflow request is unresolved"
    assert html =~ ~s(value="mix test")
    assert html =~ ~s(name="reviewer" disabled)
    assert html =~ ~s(type="hidden" name="reviewer" value="claude")
    assert html =~ "no model filesystem or shell tools"
  end

  test "Done is rendered only for saved terminal state" do
    html = panel([delivery("done")])
    assert html =~ "Done — integrated and checks passed"
    refute html =~ "Integrate approved result"
    refute html =~ "Stop workflow"
  end

  test "queued history preserves saved source, reviewer and command independent of the form" do
    saved = %{
      id: "queued",
      status: "paused",
      spec_revision_id: 6,
      reviewer: "claude",
      check_config: %{"argv" => ["mix", "test", "old_test.exs"]},
      reason: "BOSS restarted. Resume explicitly."
    }

    html = panel([], queued_workflows: [saved])
    assert html =~ "Paused — waiting for Resume"
    assert html =~ "historical snapshot"
    assert html =~ "Reviewer: Claude"
    assert html =~ "old_test.exs"
    assert html =~ "Resume uses the saved source"
    assert html =~ ~s(id="resume-queue-queued")
    assert html =~ ~s(id="cancel-queue-queued")
    assert html =~ "File conflicts are not predicted"
  end

  test "started queue history does not promise its workflow is still in bounded history" do
    saved = %{
      id: "queued",
      status: "started",
      spec_revision_id: 7,
      reviewer: "codex",
      check_config: %{"argv" => ["mix", "test"]},
      reason: nil
    }

    html = panel([], queued_workflows: [saved])
    assert html =~ "This request started a workflow. Active workflows can be stopped below."
    refute html =~ "The saved workflow is shown below"
  end

  test "unknown Queue request freezes the action as well as its input" do
    html =
      panel([],
        queue_available: true,
        start_available: false,
        uncertain: true,
        request: %{
          id: "queue-request",
          text: "mix test",
          reviewer: "claude",
          locked: true,
          action: :queue
        }
      )

    assert html =~ "Retry queue request"
    refute html =~ "Retry workflow start"
    assert html =~ ~s(value="start" disabled)
    assert html =~ ~s(name="intent" value="queue")
    assert html =~ ~s(name="reviewer" disabled)
  end

  defp panel(deliveries, opts \\ []) do
    render_component(
      &DeliveryPanel.panel/1,
      Keyword.merge(
        [
          details: %{
            task: %{state: "new"},
            pinned_revision: %{id: 7, number: 1},
            revisions: [%{id: 7, number: 1}]
          },
          deliveries: deliveries,
          request: %{id: "start-request", text: "", reviewer: "codex", locked: false},
          integration_requests: %{"delivery" => %{id: "integration-request", locked: false}},
          start_available: true,
          integrate_available: true,
          uncertain: false,
          supported: true
        ],
        opts
      )
    )
  end

  defp delivery(status) do
    %{
      id: "delivery",
      spec_revision_id: 7,
      reviewer: "codex",
      status: status,
      cycle: 2,
      reason: nil,
      cleanup: "group_empty",
      check_config: %{"argv" => ["mix", "test"]},
      intent: %{"base_branch" => "main"},
      steps: [
        %{
          number: 1,
          kind: "plan",
          status: "finished",
          input: %{},
          receipt: %{
            "report" => %{
              "summary" => "Saved plan",
              "steps" => ["Implement and verify"],
              "acceptance" => ["Keep source immutable"]
            }
          }
        },
        %{
          number: 2,
          kind: "review",
          status: "finished",
          input: %{},
          receipt: %{
            "candidate_commit" => String.duplicate("a", 40),
            "report" => %{
              "verdict" => "approved",
              "summary" => "<script>not executable</script>",
              "acceptance" => [
                %{
                  "criterion" => "Keep source immutable",
                  "status" => "passed",
                  "evidence" => "Checked source"
                }
              ],
              "issues" => []
            }
          }
        }
      ]
    }
  end
end
