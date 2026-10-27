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
