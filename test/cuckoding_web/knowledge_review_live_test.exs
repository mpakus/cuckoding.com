defmodule CuckodingWeb.KnowledgeReviewLiveTest do
  use CuckodingWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Cuckoding.Adapters.FakeAdapter
  alias Cuckoding.Execution
  alias Cuckoding.Knowledge
  alias Cuckoding.Projects
  alias Cuckoding.Repo
  alias Cuckoding.Workflows

  @now ~U[2026-09-17 00:00:00.000000Z]

  test "keyboard forms review evidence and expose publication only after approval", %{conn: conn} do
    fixture = fixture()
    candidate = extract_candidate(fixture.run.id)

    {:ok, view, html} = live(conn, ~p"/knowledge")

    assert html =~ "Review queue"
    assert has_element?(view, "#candidate-#{candidate.id}", "Durable knowledge")

    assert has_element?(
             view,
             "#candidate-#{candidate.id} details summary",
             "Evidence and redaction"
           )

    assert has_element?(view, "#candidate-#{candidate.id} input[name=reason]")
    refute html =~ ~r/tabindex="[1-9]/

    view
    |> form("#candidate-#{candidate.id} form[phx-submit=review]", %{
      "candidate_id" => candidate.id,
      "decision" => "accepted",
      "reason" => "Useful across runs"
    })
    |> render_submit()

    assert has_element?(view, "#candidate-#{candidate.id}", "accepted")
    refute has_element?(view, "#candidate-#{candidate.id}", "Publish globally")

    assert {:ok, _consolidation} = Knowledge.consolidate(fixture.project.id, manual: true)

    {:ok, growth, growth_html} = live(conn, ~p"/knowledge/growth")
    assert has_element?(growth, "h1", "Knowledge Growth")

    assert has_element?(
             growth,
             "nav[aria-label='Knowledge views'] a[aria-current=page]",
             "Growth"
           )

    assert has_element?(growth, "section[aria-labelledby=coverage-heading]", "Used by runs")
    assert has_element?(growth, "table caption", "Daily knowledge item growth")
    assert has_element?(growth, "table caption", "Recent project knowledge consolidation jobs")
    send(growth.pid, :refresh)
    assert render(growth) =~ "Knowledge growth updated."
    refute growth_html =~ ~r/tabindex="[1-9]/

    {:ok, lineage, lineage_html} = live(conn, ~p"/knowledge/lineage")
    assert has_element?(lineage, "h1", "Lineage and Usage")

    assert has_element?(
             lineage,
             "nav[aria-label='Knowledge views'] a[aria-current=page]",
             "Lineage and Usage"
           )

    assert has_element?(lineage, "ol[aria-label='Knowledge lineage graph'] article")
    assert has_element?(lineage, "a[href='/runs/#{fixture.run.id}']")
    assert has_element?(lineage, "a[href='/knowledge#candidate-#{candidate.id}']")

    item = Repo.get!(Cuckoding.Knowledge.Item, candidate.id)
    assert has_element?(lineage, "a[href='#lineage-item-#{item.id}']")
    assert has_element?(lineage, "#lineage-item-#{item.id}")
    assert has_element?(lineage, "table caption", "Accessible table alternative")
    assert has_element?(lineage, "table caption", "Knowledge usage counts")

    assert has_element?(
             lineage,
             "ol[aria-label='Knowledge lineage graph'] article a[href]"
           )

    send(lineage.pid, :refresh)
    assert render(lineage) =~ "Knowledge lineage updated."
    refute lineage_html =~ ~r/tabindex="[1-9]/

    view
    |> form("#candidate-#{candidate.id} form[phx-submit=request-publication]", %{
      "candidate_id" => candidate.id
    })
    |> render_submit()

    approval = hd(Knowledge.list_knowledge_approvals())
    assert approval.decision == "pending"
    assert has_element?(view, "section[aria-labelledby=approvals-heading]", "Decision: pending")

    view
    |> form("form[phx-submit=decide-approval]", %{
      "approval_id" => approval.id,
      "decision" => "approved",
      "reason" => "Reviewed evidence"
    })
    |> render_submit()

    assert has_element?(view, "#candidate-#{candidate.id}", "Publish globally")

    {:ok, reconnected, _html} = live(conn, ~p"/knowledge")
    assert has_element?(reconnected, "#candidate-#{candidate.id}", "accepted")
    assert has_element?(reconnected, "#candidate-#{candidate.id}", "Publish globally")
  end

  test "empty queue keeps semantic status and headings", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/knowledge")

    assert has_element?(view, "h1", "Review queue")
    assert has_element?(view, "p[role=status][aria-live=polite]")

    assert has_element?(
             view,
             "section[aria-labelledby=candidates-heading]",
             "No knowledge candidates"
           )

    assert has_element?(view, "table caption", "Global knowledge publication versions") == false
    refute html =~ ~r/tabindex="[1-9]/
  end

  defp fixture do
    suffix = System.unique_integer([:positive])
    root = Path.join(System.tmp_dir!(), "cuckoding-review-live-#{suffix}")
    repo = Path.join(root, "repo")
    workspace = Path.join(root, "workspace")
    File.mkdir_p!(repo)
    File.mkdir_p!(workspace)
    on_exit(fn -> File.rm_rf!(root) end)

    {:ok, project} =
      Projects.register(%{
        name: "Review #{suffix}",
        repo_path: repo,
        default_branch: "main",
        workspace_root: workspace,
        port_range_start: 52_000,
        port_range_end: 52_100
      })

    {:ok, policy} =
      Projects.add_config_version(%{
        project_id: project.id,
        revision: 1,
        source_hash: String.pad_leading(Integer.to_string(suffix, 16), 64, "0"),
        config_json: %{"version" => 1},
        trusted_at: @now
      })

    {:ok, workflow} =
      Workflows.publish_workflow(%{
        project_id: project.id,
        name: "default",
        version: 1,
        definition_json: %{"stages" => [%{"key" => "implement", "role" => "implementer"}]},
        published_at: @now
      })

    {:ok, board} =
      Workflows.create_board(%{
        project_id: project.id,
        workflow_version_id: workflow.id,
        name: "Review",
        concurrency_limit: 1
      })

    {:ok, task} = Workflows.create_task(%{board_id: board.id, title: "Review", position: 0})
    {:ok, _command} = Workflows.transition_task(task.id, "ready", "review:#{task.id}:ready")

    {:ok, run} =
      Execution.create_run(%{
        task_id: task.id,
        sequence: 1,
        policy_snapshot_id: policy.id,
        branch: "feature/review-#{suffix}",
        base_sha: String.duplicate("a", 40)
      })

    {:ok, attempt} =
      Execution.create_stage_attempt(%{
        run_id: run.id,
        stage_key: "implement",
        attempt: 1,
        role_key: "implementer",
        role_kind: "agent"
      })

    {:ok, _session} =
      Execution.create_agent_session(%{
        stage_attempt_id: attempt.id,
        adapter_key: "fake",
        requested_model: "fixture",
        effective_grant_json: %{"requested" => %{}, "enforced" => %{}, "unenforced" => %{}}
      })

    {:ok, _command} = Execution.transition_run(run.id, "running", "review:#{run.id}:running")
    {:ok, _command} = Execution.transition_run(run.id, "done", "review:#{run.id}:done")
    %{project: project, run: Repo.get!(Cuckoding.Execution.Run, run.id)}
  end

  defp extract_candidate(run_id) do
    operation = %{
      "kind" => "fact",
      "title" => "Durable knowledge",
      "content" => "Keep reviewed knowledge durable.",
      "confidence" => 0.9
    }

    {:ok, %{candidates: [candidate]}} =
      Knowledge.extract(run_id,
        adapter: FakeAdapter,
        adapter_options: [reply: %{"memory_operations" => [operation]}]
      )

    candidate
  end
end
