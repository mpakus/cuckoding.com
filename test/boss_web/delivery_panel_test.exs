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
    assert html =~ "An unchanged target fast-forwards"
    assert html =~ "requests a fresh review"
    assert html =~ "without automatic repair or retry"
    assert html =~ "Original base commit"
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

  test "historical failed check explains candidate changes despite exit zero" do
    saved = delivery("failed")

    step = %{
      number: 3,
      kind: "check",
      status: "failed",
      input: %{},
      receipt: %{"exit_code" => 0, "outcome" => "candidate_changed"}
    }

    html = panel([%{saved | steps: saved.steps ++ [step]}])
    assert html =~ "Checks · failed"
    assert html =~ "Process exit code: 0"
    assert html =~ "retained ref changed during verification"
    assert html =~ "generated build/test files"
    assert html =~ "Do not ignore source or tests"
    refute html =~ "Done — integrated"
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
    assert html =~ "Unknown or incomplete predictions can still cause conflicts"
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

  test "each integration stage stays stoppable and shows its current work" do
    for {kind, label} <- [
          {"merge", "Preparing merge candidate"},
          {"merge_check", "Checking merge candidate"},
          {"merge_review", "Reviewing merge candidate"}
        ] do
      saved = merged_delivery("integrating")

      steps =
        Enum.take_while(saved.steps, &(&1.kind != kind)) ++
          [%{Enum.find(saved.steps, &(&1.kind == kind)) | status: "running", receipt: %{}}]

      html = panel([%{saved | steps: steps}], start_available: false, integrate_available: false)
      assert html =~ label
      assert html =~ "Stop workflow"
      assert html =~ "Original review: Approved"
      refute html =~ "Integration review: Approved"
      refute html =~ "Integrate approved result"
      refute html =~ "Done — integrated"
    end
  end

  test "merge rejection preserves the original approval and displays each exact commit separately" do
    saved = merged_delivery("blocked")

    steps =
      List.update_at(saved.steps, -1, fn step ->
        put_in(step.receipt["report"], %{
          "verdict" => "changes_requested",
          "summary" => "Combined behavior needs correction.",
          "acceptance" => [
            %{
              "criterion" => "Keep source immutable",
              "status" => "failed",
              "evidence" => "Merge changed behavior"
            }
          ],
          "issues" => [
            %{"criterion" => "Keep source immutable", "message" => "Requires correction"}
          ]
        })
      end)

    html =
      panel([
        %{
          saved
          | reviewer: "claude",
            steps: steps,
            reason: "Integration review rejected this merge candidate."
        }
      ])

    assert section(html, "Original review") =~ "Original review: Approved"
    assert section(html, "Original review") =~ String.duplicate("a", 40)
    assert section(html, "Integration review") =~ "Integration review: Changes requested"
    assert section(html, "Integration review") =~ String.duplicate("c", 40)
    refute section(html, "Integration review") =~ String.duplicate("a", 40)
    assert section(html, "Integration candidate") =~ "Original approved commit"
    assert section(html, "Integration candidate") =~ "Target pinned for integration"
    assert section(html, "Integration candidate") =~ String.duplicate("b", 40)
    assert section(html, "Integration candidate") =~ "Merge candidate commit"
    assert html =~ "Reviewer: Claude"
    assert html =~ "Merge checks · finished"
    assert html =~ "Merge review · finished"
    refute html =~ "Done — integrated"
    refute html =~ "Integrate approved result"
    refute html =~ "Stop workflow"
  end

  test "conflict history never presents the original candidate as a successful merge" do
    saved = merged_delivery("blocked")

    steps =
      Enum.take(saved.steps, 3) |> List.update_at(-1, &%{&1 | status: "failed", receipt: %{}})

    html = panel([%{saved | steps: steps, reason: "Merge conflicts require attention."}])
    assert section(html, "Integration candidate") =~ "A merge candidate has not been recorded"
    refute section(html, "Integration candidate") =~ "Merge candidate commit"
    assert html =~ "Merge conflicts require attention"
    assert html =~ "Original review: Approved"
    refute html =~ "Integration review: Approved"
    refute html =~ "Done — integrated"
  end

  test "incomplete integration history stays explicit and cannot turn a malformed report into approval" do
    saved = merged_delivery("blocked")

    steps =
      saved.steps
      |> List.update_at(2, fn step ->
        %{
          step
          | input: %{"original_candidate" => %{}, "target_commit" => nil},
            receipt: %{"candidate_commit" => %{}}
        }
      end)
      |> List.update_at(-1, &%{&1 | receipt: %{"report" => "approved"}})

    html = panel([%{saved | steps: steps}])
    assert section(html, "Integration candidate") =~ "Unavailable"
    refute section(html, "Integration candidate") =~ String.duplicate("a", 40)
    assert html =~ "Original review: Approved"
    refute html =~ ~s(aria-label="Integration review")
    refute html =~ "Done — integrated"
  end

  test "recorded merge review alone never changes the delivery's saved terminal status" do
    html = panel([merged_delivery("integrating")])
    assert html =~ "Integration review: Approved"
    assert html =~ "Stop workflow"
    refute html =~ "Done — integrated"
    done = panel([merged_delivery("done")])
    assert done =~ "Done — integrated and checks passed"
    assert section(done, "Integration review") =~ String.duplicate("c", 40)
    refute done =~ "Stop workflow"
  end

  defp section(html, label) do
    html
    |> LazyHTML.from_fragment()
    |> LazyHTML.query(~s(section[aria-label="#{label}"]))
    |> LazyHTML.to_html()
  end

  defp merged_delivery(status) do
    saved = delivery(status)
    original = String.duplicate("a", 40)
    target = String.duplicate("b", 40)
    candidate = String.duplicate("c", 40)

    %{
      saved
      | steps:
          saved.steps ++
            [
              %{
                number: 3,
                kind: "merge",
                status: "finished",
                input: %{"original_candidate" => original, "target_commit" => target},
                receipt: %{"candidate_commit" => candidate}
              },
              %{
                number: 4,
                kind: "merge_check",
                status: "finished",
                input: %{"candidate_commit" => candidate, "target_commit" => target},
                receipt: %{}
              },
              %{
                number: 5,
                kind: "merge_review",
                status: "finished",
                input: %{"candidate_commit" => candidate, "target_commit" => target},
                receipt: %{
                  "report" => %{
                    "verdict" => "approved",
                    "summary" => "Merged behavior reviewed.",
                    "acceptance" => [],
                    "issues" => []
                  }
                }
              }
            ]
    }
  end

  test "saved scope predictions distinguish files and directories and escape paths" do
    delivery = delivery("planning")
    [plan | rest] = delivery.steps

    report =
      Map.put(plan.receipt["report"], "file_scopes", [
        %{"path" => "lib/boss", "kind" => "directory"},
        %{"path" => "test/<scope>.exs", "kind" => "file"}
      ])

    delivery = %{delivery | steps: [%{plan | receipt: %{"report" => report}} | rest]}
    html = panel([delivery])
    assert html =~ "Predicted file scopes"
    assert html =~ "Directory:"
    assert html =~ "lib/boss"
    assert html =~ "File:"
    assert html =~ "test/&lt;scope&gt;.exs"
    assert html =~ "unpredicted edits or semantic conflicts"
    refute html =~ "File scope is unknown"
    refute html =~ "Waiting for an overlapping workflow"
  end

  test "legacy or unknown scopes warn without claiming conflict freedom" do
    delivery = delivery("planning")
    assert panel([delivery]) =~ "File scope is unknown"

    [plan | rest] = delivery.steps
    report = Map.put(plan.receipt["report"], "file_scopes", nil)
    delivery = %{delivery | steps: [%{plan | receipt: %{"report" => report}} | rest]}
    assert panel([delivery]) =~ "potential conflicts remain"
    refute panel([delivery]) =~ "Waiting for an overlapping workflow"
  end

  test "only a reported overlap shows waiting and preserves Stop" do
    delivery = delivery("planning")
    html = panel([delivery], scope_blockers: %{delivery.id => ["peer"]})
    assert html =~ "Waiting for file scope"
    refute html =~ "Preparing plan"
    assert html =~ "Waiting for an overlapping workflow to finish"
    assert html =~ "Implementation has not started"
    assert html =~ ~s(id="stop-delivery-#{delivery.id}")
    refute panel([delivery], scope_blockers: %{}) =~ "Waiting for an overlapping workflow"
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
