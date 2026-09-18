defmodule Cuckoding.Knowledge.PublicationServiceTest do
  use Cuckoding.DataCase, async: false

  alias Cuckoding.Adapters.FakeAdapter
  alias Cuckoding.Execution
  alias Cuckoding.Execution.RunEvent
  alias Cuckoding.Knowledge
  alias Cuckoding.Knowledge.Item
  alias Cuckoding.Knowledge.Publication
  alias Cuckoding.Knowledge.SkillPackage
  alias Cuckoding.Projects
  alias Cuckoding.Repo
  alias Cuckoding.Workflows

  @now ~U[2026-09-17 00:00:00.000000Z]
  @actor "local-user"
  @canary "CUCKODING_SECRET_CANARY_0704"

  setup do
    root = Path.join(System.tmp_dir!(), "cuckoding-publish-#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)

    fixture = fixture(root)
    %{fixture: Map.put(fixture, :global_root, Path.join(root, "global"))}
  end

  test "global publication requires matching approval and revoke/rollback preserve versions", %{
    fixture: fixture
  } do
    candidate = extract_candidate(fixture, operation("fact", "Durable rule", "Keep it durable."))

    assert {:ok, accepted} =
             Knowledge.review_candidate(candidate.id, "accepted", @actor, "Useful project fact")

    assert accepted.decision == "accepted"

    assert %Item{scope: "project", project_id: project_id} =
             Repo.get(Item, accepted.accepted_item_id)

    assert project_id == fixture.project.id

    {:ok, wrong_approval} =
      Workflows.request_approval(%{
        id: Cuckoding.Identifier.generate(),
        run_id: fixture.run.id,
        kind: "knowledge_publication:#{Cuckoding.Identifier.generate()}"
      })

    {:ok, wrong_approval} =
      Workflows.decide_approval(wrong_approval.id, "approved", @actor, "Wrong subject")

    assert {:error, :matching_human_approval_required} =
             Knowledge.publish(candidate.id, wrong_approval.id, @actor,
               global_root: fixture.global_root
             )

    assert {:ok, approval} = Knowledge.request_publication(candidate.id)

    assert {:error, :matching_human_approval_required} =
             Knowledge.publish(candidate.id, approval.id, @actor,
               global_root: fixture.global_root
             )

    assert {:ok, approved} =
             Workflows.decide_approval(approval.id, "approved", @actor, "Share this fact")

    assert {:ok, published} =
             Knowledge.publish(candidate.id, approved.id, @actor,
               global_root: fixture.global_root
             )

    global = Repo.get!(Item, published.knowledge_item_id)
    assert global.scope == "global"
    assert global.status == "global"
    assert global.version == 1
    assert published.content_hash == global.content_hash
    assert File.read!(Path.join(fixture.global_root, global.file_path)) == published.content

    assert {:ok, revoke_approval} = Knowledge.request_revocation(published.id)

    assert {:ok, revoke_approval} =
             Workflows.decide_approval(
               revoke_approval.id,
               "approved",
               @actor,
               "Outdated guidance"
             )

    assert {:ok, revoked} =
             Knowledge.revoke(published.id, revoke_approval.id, @actor,
               global_root: fixture.global_root
             )

    revoked_item = Repo.get!(Item, global.id)
    assert revoked.action == "revoke"
    assert revoked.version == 2
    assert revoked.previous_publication_id == published.id
    assert revoked_item.status == "revoked"
    assert revoked_item.version == 2

    assert {:ok, rollback_approval} = Knowledge.request_rollback(revoked.id, 1)

    assert {:ok, rollback_approval} =
             Workflows.decide_approval(
               rollback_approval.id,
               "approved",
               @actor,
               "Restore reviewed version"
             )

    assert {:ok, rolled_back} =
             Knowledge.rollback(revoked.id, 1, rollback_approval.id, @actor,
               global_root: fixture.global_root
             )

    restored_item = Repo.get!(Item, global.id)
    assert rolled_back.action == "rollback"
    assert rolled_back.version == 3
    assert restored_item.status == "global"
    assert restored_item.version == 3
    assert File.read!(Path.join(fixture.global_root, global.file_path)) == rolled_back.content
    assert Repo.aggregate(Publication, :count) == 3

    event_types =
      Repo.all(
        from(event in RunEvent,
          where: event.run_id == ^fixture.run.id,
          select: event.event_type
        )
      )

    assert "knowledge.candidate.accepted" in event_types
    assert "knowledge.published" in event_types
    assert "knowledge.revoked" in event_types
    assert "knowledge.rolled_back" in event_types

    assert_raise Exqlite.Error, ~r/append-only/, fn ->
      Repo.update_all(from(row in Publication, where: row.id == ^published.id),
        set: [reason: "tampered"]
      )
    end
  end

  test "policy limits automatic review and rejected candidates never create files", %{
    fixture: fixture
  } do
    fact = extract_candidate(fixture, operation("fact", "Allowed fact", "Fact body."))

    assert {:ok, auto} =
             Knowledge.review_candidate(fact.id, "accepted", "system", "Configured policy",
               automatic: true
             )

    assert auto.decision == "accepted"

    second_fixture = fixture(Path.join(fixture.root, "second"))

    pattern =
      extract_candidate(second_fixture, operation("pattern", "Manual pattern", "Pattern body."))

    assert {:error, :project_auto_accept_not_allowed} =
             Knowledge.review_candidate(pattern.id, "accepted", "system", "Not allowed",
               automatic: true
             )

    assert {:ok, rejected} =
             Knowledge.review_candidate(pattern.id, "rejected", @actor, "Not reusable")

    assert rejected.decision == "rejected"
    assert is_nil(rejected.accepted_item_id)
    refute Repo.get(Item, pattern.id)
  end

  test "approved recipes produce a portable redacted skill package", %{fixture: fixture} do
    candidate =
      extract_candidate(
        fixture,
        operation(
          "recipe",
          "Run focused checks",
          "Run the focused gate without #{@canary}."
        ),
        secrets: [@canary]
      )

    assert {:ok, _accepted} =
             Knowledge.review_candidate(candidate.id, "accepted", @actor, "Reusable recipe")

    assert {:ok, approval} = Knowledge.request_publication(candidate.id)

    assert {:ok, approval} =
             Workflows.decide_approval(approval.id, "approved", @actor, "Publish the recipe")

    assert {:ok, publication} =
             Knowledge.publish(candidate.id, approval.id, @actor,
               global_root: fixture.global_root,
               skill: true,
               secrets: [@canary]
             )

    package = Repo.get_by!(SkillPackage, publication_id: publication.id)
    skill_path = Path.join(fixture.global_root, package.file_path)
    skill = File.read!(skill_path)
    manifest = File.read!(Path.join(Path.dirname(skill_path), "manifest.json"))

    assert skill =~ ~s(name: "run-focused-checks")
    assert skill =~ "## Safety"
    assert skill =~ "## Verification"
    assert manifest =~ ~s("version": "1.0.0")
    refute skill =~ @canary
    refute publication.content =~ @canary
    assert package.content_hash == sha256(skill)

    assert_raise Exqlite.Error, ~r/append-only/, fn ->
      Repo.update_all(from(row in SkillPackage, where: row.id == ^package.id),
        set: [version: "9.9.9"]
      )
    end
  end

  test "accepted updates supersede rather than overwrite project history", %{fixture: fixture} do
    first =
      extract_candidate(fixture, operation("fact", "Stable rule", "Original reviewed content."))

    assert {:ok, first} =
             Knowledge.review_candidate(first.id, "accepted", @actor, "Initial version")

    next_run = additional_run(fixture)

    second =
      extract_candidate(
        %{fixture | run: next_run},
        operation("fact", "Stable rule", "Corrected reviewed content.")
      )

    assert second.operation == "update"
    assert second.target_item_id == first.accepted_item_id

    assert {:ok, second} =
             Knowledge.review_candidate(second.id, "accepted", @actor, "Correction")

    replacement = Repo.get!(Item, second.accepted_item_id)
    assert replacement.supersedes_id == first.accepted_item_id
    assert Repo.get!(Item, first.accepted_item_id).status == "project"
    assert Repo.aggregate(Item, :count) == 2
  end

  defp fixture(root) do
    suffix = System.unique_integer([:positive])
    repo = Path.join(root, "repo")
    workspace = Path.join(root, "workspace")
    File.mkdir_p!(repo)
    File.mkdir_p!(workspace)

    {:ok, project} =
      Projects.register(%{
        name: "Publication #{suffix}",
        repo_path: repo,
        default_branch: "main",
        workspace_root: workspace,
        port_range_start: 51_000,
        port_range_end: 51_100
      })

    {:ok, policy} =
      Projects.add_config_version(%{
        project_id: project.id,
        revision: 1,
        source_hash: String.pad_leading(Integer.to_string(suffix, 16), 64, "0"),
        config_json: %{
          "version" => 1,
          "knowledge" => %{"auto_accept" => ["fact", "recipe"]}
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
        name: "Knowledge",
        concurrency_limit: 1
      })

    {:ok, task} = Workflows.create_task(%{board_id: board.id, title: "Knowledge", position: 0})

    {:ok, _command} =
      Workflows.transition_task(task.id, "ready", "publish:#{task.id}:ready")

    {:ok, run} =
      Execution.create_run(%{
        task_id: task.id,
        sequence: 1,
        policy_snapshot_id: policy.id,
        branch: "feature/knowledge-#{suffix}",
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

    assert {:ok, _command} =
             Execution.transition_run(run.id, "running", "publish:#{run.id}:running")

    assert {:ok, _command} = Execution.transition_run(run.id, "done", "publish:#{run.id}:done")

    %{
      project: project,
      run: Repo.get!(Cuckoding.Execution.Run, run.id),
      root: root,
      board: board,
      policy: policy
    }
  end

  defp additional_run(fixture) do
    suffix = System.unique_integer([:positive])
    {:ok, task} = Workflows.create_task(%{board_id: fixture.board.id, title: "More", position: 1})
    {:ok, _command} = Workflows.transition_task(task.id, "ready", "more:#{task.id}:ready")

    {:ok, run} =
      Execution.create_run(%{
        task_id: task.id,
        sequence: 1,
        policy_snapshot_id: fixture.policy.id,
        branch: "feature/more-#{suffix}",
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

    {:ok, _session} =
      Execution.create_agent_session(%{
        stage_attempt_id: attempt.id,
        adapter_key: "fake",
        requested_model: "fixture",
        effective_grant_json: %{"requested" => %{}, "enforced" => %{}, "unenforced" => %{}}
      })

    {:ok, _command} = Execution.transition_run(run.id, "running", "more:#{run.id}:running")
    {:ok, _command} = Execution.transition_run(run.id, "done", "more:#{run.id}:done")
    Repo.get!(Cuckoding.Execution.Run, run.id)
  end

  defp extract_candidate(fixture, operation, options \\ []) do
    assert {:ok, %{candidates: [candidate]}} =
             Knowledge.extract(fixture.run.id,
               adapter: FakeAdapter,
               adapter_options: [reply: %{"memory_operations" => [operation]}],
               secrets: Keyword.get(options, :secrets, [])
             )

    candidate
  end

  defp operation(kind, title, content) do
    %{
      "kind" => kind,
      "title" => title,
      "content" => content,
      "confidence" => 0.9
    }
  end

  defp sha256(value), do: :crypto.hash(:sha256, value) |> Base.encode16(case: :lower)
end
