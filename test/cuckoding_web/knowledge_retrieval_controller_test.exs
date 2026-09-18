defmodule CuckodingWeb.KnowledgeRetrievalControllerTest do
  use CuckodingWeb.ConnCase, async: false

  alias Cuckoding.Execution
  alias Cuckoding.Knowledge
  alias Cuckoding.Knowledge.Store
  alias Cuckoding.Knowledge.Sync
  alias Cuckoding.Projects
  alias Cuckoding.Workflows

  test "POST /api/knowledge/retrieve requires and honors a run-scoped capability", %{conn: conn} do
    fixture = fixture()
    assert {:ok, capability} = Knowledge.issue_retrieval_token(fixture.run.id, fixture.attempt.id)

    assert conn
           |> post(~p"/api/knowledge/retrieve", %{"query" => "loopback safety"})
           |> json_response(401) == %{"error" => "authorization_required"}

    response =
      conn
      |> put_req_header("authorization", "Bearer #{capability.token}")
      |> post(~p"/api/knowledge/retrieve", %{"query" => "loopback safety", "limit" => 2})
      |> json_response(200)

    assert [%{"id" => item_id, "citation" => citation}] = response["results"]
    assert item_id == fixture.item_id
    assert citation == "knowledge:#{fixture.item_id}@v1"
  end

  defp fixture do
    suffix = System.unique_integer([:positive])
    root = Path.join(System.tmp_dir!(), "cuckoding-retrieval-web-#{suffix}")
    repo = Path.join(root, "repo")
    workspace = Path.join(root, "workspace")
    File.mkdir_p!(repo)
    File.mkdir_p!(workspace)
    on_exit(fn -> File.rm_rf!(root) end)

    {:ok, project} =
      Projects.register(%{
        name: "Retrieval #{suffix}",
        repo_path: repo,
        default_branch: "main",
        workspace_root: workspace,
        port_range_start: 53_000,
        port_range_end: 53_100
      })

    config = %{"version" => 1, "knowledge" => %{"global_retrieval_enabled" => false}}

    {:ok, policy} =
      Projects.add_config_version(%{
        project_id: project.id,
        revision: 1,
        source_hash: sha256(Jason.encode!(config)),
        config_json: config,
        trusted_at: Cuckoding.Clock.wall_now()
      })

    {:ok, workflow} =
      Workflows.publish_workflow(%{
        project_id: project.id,
        name: "default",
        version: 1,
        definition_json: %{"stages" => [%{"key" => "implement", "role" => "implementer"}]},
        published_at: Cuckoding.Clock.wall_now()
      })

    {:ok, board} =
      Workflows.create_board(%{
        project_id: project.id,
        workflow_version_id: workflow.id,
        name: "Knowledge",
        concurrency_limit: 1
      })

    {:ok, task} = Workflows.create_task(%{board_id: board.id, title: "Retrieve", position: 0})
    {:ok, _command} = Workflows.transition_task(task.id, "ready", "web:#{task.id}:ready")

    {:ok, run} =
      Execution.create_run(%{
        task_id: task.id,
        sequence: 1,
        policy_snapshot_id: policy.id,
        branch: "feature/retrieve-#{suffix}",
        base_sha: String.duplicate("b", 40)
      })

    {:ok, attempt} =
      Execution.create_stage_attempt(%{
        run_id: run.id,
        stage_key: "implement",
        attempt: 1,
        role_key: "implementer",
        role_kind: "agent"
      })

    item_id = Cuckoding.Identifier.generate()
    raw = document(item_id)
    assert {:ok, _document} = Store.write_project_document(project, "facts/loopback.md", raw)
    assert {:ok, _sync} = Sync.run_project(project)
    %{run: run, attempt: attempt, item_id: item_id}
  end

  defp document(id) do
    now = DateTime.to_iso8601(Cuckoding.Clock.wall_now())

    """
    ---
    id: #{Jason.encode!(id)}
    kind: "fact"
    title: "Loopback safety"
    scope: "project"
    status: "project"
    version: 1
    confidence: 1.0
    valid_from: #{Jason.encode!(now)}
    invalid_at: null
    supersedes: null
    evidence: {"source":"test"}
    produced_by: {"runtime":"fixture"}
    triggers: ["loopback safety"]
    review: {"approver":"tester","date":#{Jason.encode!(now)}}
    ---
    # Loopback safety

    Bind the control plane to loopback only.
    """
  end

  defp sha256(value), do: :crypto.hash(:sha256, value) |> Base.encode16(case: :lower)
end
