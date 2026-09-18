defmodule Cuckoding.Knowledge.ExtractorTest do
  use Cuckoding.DataCase, async: false

  alias Cuckoding.ActivityStream
  alias Cuckoding.Adapters.FakeAdapter
  alias Cuckoding.Adapters.Types
  alias Cuckoding.Execution
  alias Cuckoding.Knowledge
  alias Cuckoding.Knowledge.Candidate
  alias Cuckoding.Knowledge.Job
  alias Cuckoding.Projects
  alias Cuckoding.Repo
  alias Cuckoding.Workflows

  @fixture Path.expand("../../fixtures/knowledge/valid.md", __DIR__)
  @item_id "019b0000-0000-7000-8000-000000000701"
  @canary "CUCKODING_SECRET_CANARY_0702"
  @now ~U[2026-09-18 01:00:00.000000Z]

  setup do
    root = Path.join(System.tmp_dir!(), "cuckoding-extract-#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    %{fixture: fixture(root)}
  end

  test "fake adapter extraction classifies operations and redacts both boundaries", %{
    fixture: fixture
  } do
    {:ok, existing_document} = Cuckoding.Knowledge.Parser.parse_file(@fixture)

    operations = [
      operation("fact", "Duplicate", existing_document.body, 0.9),
      operation("fact", "Use durable workflow state", "A refined durable-state rule.", 0.8),
      operation(
        "recipe",
        "Run focused tests",
        "Never print #{@canary}; run the focused suite.",
        0.7
      ),
      operation("pattern", "Replace old state rule", "A replacement pattern.", 0.85)
      |> Map.put("supersedes_id", @item_id)
    ]

    assert {:ok, %{job: job, candidates: candidates}} =
             Knowledge.extract(fixture.run.id,
               adapter: FakeAdapter,
               adapter_options: [reply: %{"memory_operations" => operations}],
               secrets: [@canary],
               input_budget: 8_192
             )

    assert job.state == "completed"
    assert job.runtime == "fake"
    assert job.summary_json == %{"candidate_count" => 4}
    assert Enum.sort(Enum.map(candidates, & &1.operation)) == ~w(add noop supersede update)

    duplicate = Enum.find(candidates, &(&1.operation == "noop"))
    update = Enum.find(candidates, &(&1.operation == "update"))
    supersede = Enum.find(candidates, &(&1.operation == "supersede"))
    added = Enum.find(candidates, &(&1.operation == "add"))
    assert duplicate.target_item_id == @item_id
    assert update.target_item_id == @item_id
    assert supersede.target_item_id == @item_id
    assert is_nil(added.target_item_id)
    assert added.content =~ "[REDACTED]"
    refute added.content =~ @canary

    assert Enum.all?(candidates, fn candidate ->
             candidate.evidence_json["run_id"] == fixture.run.id and
               fixture.activity_id in candidate.evidence_json["event_ids"] and
               fixture.artifact_id in candidate.evidence_json["artifact_event_ids"] and
               candidate.evidence_json["repository_sha"] == fixture.run.base_sha
           end)

    database_text = Repo.all(Candidate) |> inspect()

    refute database_text =~ @canary

    assert {:ok, %{job: same_job, candidates: same_candidates}} =
             Knowledge.extract(fixture.run.id,
               adapter: FakeAdapter,
               adapter_options: [reply: %{"memory_operations" => []}],
               secrets: [@canary]
             )

    assert same_job.id == job.id
    assert length(same_candidates) == 4
  end

  test "disabled policy and incomplete runs cannot start extraction", %{fixture: fixture} do
    queued =
      fixture(
        root: fixture.root,
        extraction: "on_completion",
        complete?: false,
        knowledge?: false
      )

    disabled = fixture(root: fixture.root, extraction: "off", knowledge?: false)

    assert {:error, :run_not_complete} = Knowledge.extract(queued.run.id)

    assert {:error, :knowledge_extraction_disabled} =
             Knowledge.extract(disabled.run.id,
               adapter: FakeAdapter,
               adapter_options: [reply: %{"memory_operations" => []}]
             )

    refute Repo.get_by(Job, scope_id: queued.run.id)
    refute Repo.get_by(Job, scope_id: disabled.run.id)
  end

  test "malformed synthesis fails the durable job without persisting candidates", %{
    fixture: fixture
  } do
    assert {:error, :missing_memory_operations} =
             Knowledge.extract(fixture.run.id,
               adapter: FakeAdapter,
               adapter_options: [reply: %{}]
             )

    assert Repo.get_by!(Job, scope_id: fixture.run.id).state == "failed"
    assert Repo.aggregate(Candidate, :count) == 0
  end

  defp fixture(options) when is_list(options),
    do: options |> Keyword.fetch!(:root) |> build_fixture(options)

  defp fixture(root) when is_binary(root), do: build_fixture(root, root: root)

  defp build_fixture(root, options) do
    suffix = System.unique_integer([:positive])
    repo = Path.join(root, "repo-#{suffix}")
    workspace = Path.join(root, "workspace-#{suffix}")
    File.mkdir_p!(repo)
    File.mkdir_p!(workspace)

    {:ok, project} =
      Projects.register(%{
        name: "Extraction #{suffix}",
        repo_path: repo,
        default_branch: "main",
        workspace_root: workspace,
        port_range_start: 49_000,
        port_range_end: 49_100
      })

    {:ok, policy} =
      Projects.add_config_version(%{
        project_id: project.id,
        revision: 1,
        source_hash: String.pad_leading(Integer.to_string(suffix, 16), 64, "0"),
        config_json: %{
          "version" => 1,
          "knowledge" => %{"extraction" => Keyword.get(options, :extraction, "on_completion")}
        },
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
        name: "Extraction board",
        concurrency_limit: 1
      })

    {:ok, task} = Workflows.create_task(%{board_id: board.id, title: "Extract", position: 0})
    {:ok, _command} = Workflows.transition_task(task.id, "ready", "extract:#{task.id}:ready")

    {:ok, run} =
      Execution.create_run(%{
        task_id: task.id,
        sequence: 1,
        policy_snapshot_id: policy.id,
        branch: "feature/extract-#{suffix}",
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

    {:ok, session} =
      Execution.create_agent_session(%{
        stage_attempt_id: attempt.id,
        adapter_key: "fake",
        requested_model: "fixture",
        effective_grant_json: %{"requested" => %{}, "enforced" => %{}, "unenforced" => %{}}
      })

    if Keyword.get(options, :knowledge?, true) do
      {:ok, root_path} = Knowledge.ensure_project_layout(project)
      File.cp!(@fixture, Path.join(root_path, "facts/durable-state.md"))
      {:ok, _sync} = Knowledge.sync_project(project)
    end

    {:ok, activity} =
      ActivityStream.record(
        session,
        event("activity", 1, "activity.summary", "Public #{@canary}")
      )

    {:ok, artifact} =
      ActivityStream.record(session, event("artifact", 2, "artifact.created", "Public artifact"))

    run = if Keyword.get(options, :complete?, true), do: complete(run), else: run

    %{
      root: root,
      run: run,
      activity_id: activity.result["event_id"],
      artifact_id: artifact.result["event_id"]
    }
  end

  defp complete(run) do
    assert {:ok, _command} =
             Execution.transition_run(run.id, "running", "extract:#{run.id}:running")

    assert {:ok, _command} = Execution.transition_run(run.id, "done", "extract:#{run.id}:done")
    Repo.get!(Cuckoding.Execution.Run, run.id)
  end

  defp event(id, sequence, type, summary) do
    %Types.Event{
      event_id: id,
      sequence: sequence,
      type: type,
      public_summary: summary,
      metadata: if(type == "artifact.created", do: %{"path" => "report.md"}, else: %{}),
      trust: :untrusted
    }
  end

  defp operation(kind, title, content, confidence) do
    %{"kind" => kind, "title" => title, "content" => content, "confidence" => confidence}
  end
end
