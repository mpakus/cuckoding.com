defmodule Cuckoding.Knowledge.ConsolidatorTest do
  use Cuckoding.DataCase, async: false

  alias Cuckoding.Execution
  alias Cuckoding.Knowledge
  alias Cuckoding.Knowledge.ConsolidationJob
  alias Cuckoding.Knowledge.IndexRevision
  alias Cuckoding.Knowledge.Item
  alias Cuckoding.Projects
  alias Cuckoding.Repo
  alias Cuckoding.Workflows

  @canary "CUCKODING_SECRET_CANARY_0703"
  @now ~U[2026-09-17 00:00:00.000000Z]

  setup do
    root =
      Path.join(System.tmp_dir!(), "cuckoding-consolidate-#{System.unique_integer([:positive])}")

    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)

    project = project(root)
    {:ok, knowledge_root} = Knowledge.ensure_project_layout(project)
    %{project: project, root: knowledge_root}
  end

  test "deduplicates the index, retains superseded files, redacts, and proposes expiry", %{
    project: project,
    root: root
  } do
    old_id = id(1)
    new_id = id(2)
    duplicate_a = id(3)
    duplicate_b = id(4)
    observation = id(5)

    write_item(root, "facts/a-old.md", old_id, "fact", "Old policy", "Old value.")

    write_item(
      root,
      "facts/b-new.md",
      new_id,
      "fact",
      "New #{@canary}",
      "New value.",
      supersedes: old_id,
      valid_from: "2026-09-16T00:00:00.000000Z"
    )

    write_item(root, "facts/c-duplicate-a.md", duplicate_a, "fact", "Duplicate A", "Same.")

    write_item(
      root,
      "facts/d-duplicate-b.md",
      duplicate_b,
      "fact",
      "Duplicate B",
      "Same.",
      valid_from: "2026-09-16T00:00:00.000000Z"
    )

    write_item(
      root,
      "observations/a-stale.md",
      observation,
      "observation",
      "Stale observation",
      "Review this.",
      valid_from: "2025-01-01T00:00:00.000000Z"
    )

    assert {:ok, %{inserted: inserted, errors: []}} = Knowledge.sync_project(project)

    assert Enum.sort(inserted) ==
             Enum.sort([old_id, new_id, duplicate_a, duplicate_b, observation])

    assert {:ok, %{job: job, revision: revision}} =
             Knowledge.consolidate(project.id, manual: true, secrets: [@canary])

    index = File.read!(Path.join(root, "INDEX.md"))
    assert index =~ "New \\[REDACTED\\]"
    refute index =~ @canary
    refute index =~ "Old policy"
    refute index =~ "Duplicate A"
    assert index =~ "Duplicate B"
    assert byte_size(index) <= 32_768

    assert File.exists?(Path.join(root, "facts/a-old.md"))
    assert File.exists?(Path.join(root, "facts/b-new.md"))
    assert Repo.aggregate(Item, :count) == 5

    assert job.state == "completed"
    assert job.summary_json["superseded_ids"] == [old_id]
    assert job.summary_json["duplicate_groups"] == [[duplicate_a, duplicate_b]]
    assert job.summary_json["expiry_proposal_ids"] == [observation]
    assert revision.content == index
    refute revision.content =~ @canary
  end

  test "automatic consolidation waits for an idle project while manual work can proceed", %{
    project: project,
    root: root
  } do
    write_item(root, "facts/item.md", id(10), "fact", "One", "Value.")
    active_stage(project)

    assert {:error, :project_has_active_stage} = Knowledge.consolidate(project.id)
    refute Repo.get_by(ConsolidationJob, project_id: project.id)

    assert {:ok, %{job: %{state: "completed"}}} =
             Knowledge.consolidate(project.id, manual: true)
  end

  test "a killed job resumes from its durable scan checkpoint and versions later rewrites", %{
    project: project,
    root: root
  } do
    write_item(root, "facts/one.md", id(20), "fact", "One", "First.")

    assert {:error, :simulated_process_exit} =
             Knowledge.consolidate(project.id, manual: true, interrupt_after: :scan)

    interrupted = Repo.get_by!(ConsolidationJob, project_id: project.id)
    assert interrupted.state == "running"
    assert interrupted.checkpoint_json == %{"phase" => "scanned"}
    refute File.exists?(Path.join(root, "INDEX.md"))

    assert {:ok, %{job: resumed, revision: first, mode: :resumed}} =
             Knowledge.consolidate(project.id, manual: true)

    assert resumed.id == interrupted.id
    assert resumed.revision == 1
    assert Repo.aggregate(IndexRevision, :count) == 1

    write_item(root, "facts/two.md", id(21), "fact", "Two", "Second.")

    assert {:ok, %{job: rerun, revision: second, mode: :started}} =
             Knowledge.consolidate(project.id, manual: true)

    assert rerun.id == interrupted.id
    assert rerun.revision == 2
    assert second.job_revision == 2
    assert second.previous_hash == first.content_hash
    assert Repo.aggregate(IndexRevision, :count) == 2
  end

  test "refuses a symlinked index instead of writing outside the knowledge root", %{
    project: project,
    root: root
  } do
    outside = Path.join(Path.dirname(root), "outside-index.md")
    File.write!(outside, "keep")
    File.ln_s!(outside, Path.join(root, "INDEX.md"))

    assert {:error, :knowledge_index_symlink} =
             Knowledge.consolidate(project.id, manual: true)

    assert File.read!(outside) == "keep"
    assert Repo.get_by!(ConsolidationJob, project_id: project.id).state == "failed"
  end

  defp project(root) do
    suffix = System.unique_integer([:positive])
    repo = Path.join(root, "repo")
    workspace = Path.join(root, "workspace")
    File.mkdir_p!(repo)
    File.mkdir_p!(workspace)

    {:ok, project} =
      Projects.register(%{
        name: "Consolidation #{suffix}",
        repo_path: repo,
        default_branch: "main",
        workspace_root: workspace,
        port_range_start: 50_000,
        port_range_end: 50_100
      })

    project
  end

  defp active_stage(project) do
    suffix = System.unique_integer([:positive])

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
        name: "Active",
        concurrency_limit: 1
      })

    {:ok, task} = Workflows.create_task(%{board_id: board.id, title: "Work", position: 0})

    {:ok, run} =
      Execution.create_run(%{
        task_id: task.id,
        sequence: 1,
        policy_snapshot_id: policy.id,
        branch: "feature/active-#{suffix}",
        base_sha: String.duplicate("a", 40)
      })

    Execution.create_stage_attempt(%{
      run_id: run.id,
      stage_key: "implement",
      attempt: 1,
      role_key: "implementer",
      role_kind: "agent"
    })
  end

  defp write_item(root, relative, item_id, kind, title, body, options \\ []) do
    path = Path.join(root, relative)
    File.mkdir_p!(Path.dirname(path))
    supersedes = Keyword.get(options, :supersedes)
    valid_from = Keyword.get(options, :valid_from, "2026-09-15T00:00:00.000000Z")

    File.write!(
      path,
      """
      ---
      id: "#{item_id}"
      kind: #{kind}
      title: "#{title}"
      scope: project
      status: project
      version: 1
      confidence: 0.9
      valid_from: "#{valid_from}"
      invalid_at: null
      supersedes: #{if supersedes, do: ~s("#{supersedes}"), else: "null"}
      evidence:
        source: test
      produced_by:
        runtime: test
      triggers:
        - "during tests"
      review: null
      ---
      # #{title}

      #{body}
      """
    )
  end

  defp id(number), do: "019b0000-0000-7000-8000-#{String.pad_leading(to_string(number), 12, "0")}"
end
