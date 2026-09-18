defmodule Cuckoding.Knowledge.InjectionTest do
  use Cuckoding.DataCase, async: false

  alias Cuckoding.Adapters.FakeAdapter
  alias Cuckoding.Adapters.Types
  alias Cuckoding.Execution
  alias Cuckoding.Knowledge
  alias Cuckoding.Knowledge.Retrieval
  alias Cuckoding.Knowledge.RetrievalToken
  alias Cuckoding.Knowledge.Usage
  alias Cuckoding.Projects
  alias Cuckoding.Workflows

  @actor "local-user"
  @canary "CUCKODING_RETRIEVAL_SECRET_0705"

  setup do
    root =
      Path.join(System.tmp_dir!(), "cuckoding-injection-#{System.unique_integer([:positive])}")

    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    %{root: root}
  end

  test "published knowledge is injected into the next run and corrections update lineage", %{
    root: root
  } do
    fixture = fixture(root, true)
    candidate = extract(fixture, "Durable rule", "Keep state durable.")

    assert {:ok, accepted} =
             Knowledge.review_candidate(candidate.id, "accepted", @actor, "Useful evidence")

    assert {:ok, _consolidation} = Knowledge.consolidate(fixture.project.id, manual: true)
    assert {:ok, approval} = Knowledge.request_publication(candidate.id)

    assert {:ok, approval} =
             Workflows.decide_approval(approval.id, "approved", @actor, "Share reviewed evidence")

    assert {:ok, publication} =
             Knowledge.publish(candidate.id, approval.id, @actor,
               global_root: fixture.global_root
             )

    next = next_run(fixture, "Apply the durable rule")
    request = request(fixture, next)

    assert {:ok, prepared} =
             Knowledge.prepare_injection(request, global_root: fixture.global_root)

    assert [%{"id" => "project-index", "trust" => "untrusted"} | items] = prepared.knowledge
    assert Enum.any?(items, &(&1["id"] == accepted.accepted_item_id))
    assert Enum.any?(items, &(&1["id"] == publication.knowledge_item_id))
    assert Enum.all?(items, &(&1["trust"] == "untrusted"))

    assert {:ok, _grant} = FakeAdapter.render_config(prepared, [])
    assert :ok = Knowledge.record_injection(prepared)
    config = File.read!(Path.join([next.run_dir, "agent", "fake-adapter.json"]))
    assert config =~ "untrusted"
    refute File.exists?(Path.join(fixture.repo, "AGENTS.md"))

    injected = Repo.all(from(usage in Usage, where: usage.run_id == ^next.run.id))
    assert Enum.count(injected, &(&1.kind == "injected")) == 2
    assert :ok = Knowledge.record_injection(prepared)
    assert Repo.aggregate(from(usage in Usage, where: usage.kind == "injected"), :count) == 2

    assert {:ok, capability} = Knowledge.issue_retrieval_token(next.run.id, next.attempt.id)
    refute Repo.get_by(RetrievalToken, token_hash: capability.token)

    assert {:ok, %{results: results}} =
             Knowledge.retrieve(capability.token, "durable rule #{@canary}",
               global_root: fixture.global_root
             )

    assert Enum.any?(results, &(&1.id == accepted.accepted_item_id))
    assert Enum.any?(results, &(&1.id == publication.knowledge_item_id))
    assert Enum.all?(results, &String.starts_with?(&1.citation, "knowledge:"))

    citation = hd(results).citation
    assert :ok = Knowledge.record_citations(next.run.id, next.attempt.id, citation)
    assert Repo.aggregate(Retrieval, :count) == 1
    refute inspect(Repo.one!(Retrieval)) =~ @canary
    assert Repo.aggregate(from(usage in Usage, where: usage.kind == "retrieved"), :count) == 2
    assert Repo.aggregate(from(usage in Usage, where: usage.kind == "cited"), :count) == 1

    usage = Repo.one!(from(usage in Usage, limit: 1))

    assert_raise Exqlite.Error, ~r/append-only/, fn ->
      Repo.update_all(from(row in Usage, where: row.id == ^usage.id), set: [kind: "accepted"])
    end

    assert {:ok, _command} =
             Execution.transition_run(next.run.id, "running", "next:#{next.run.id}:running")

    assert {:ok, _command} =
             Execution.transition_run(next.run.id, "done", "next:#{next.run.id}:done")

    correction =
      extract(%{fixture | run: Repo.reload!(next.run)}, "Durable rule", "Corrected rule.")

    assert correction.operation == "update"
    assert correction.target_item_id == accepted.accepted_item_id

    assert {:ok, corrected} =
             Knowledge.review_candidate(
               correction.id,
               "accepted",
               @actor,
               "Correct prior guidance"
             )

    assert corrected.accepted_item_id != accepted.accepted_item_id

    outcomes = Repo.all(from(usage in Usage, where: usage.run_id == ^next.run.id))

    assert Enum.any?(
             outcomes,
             &(&1.kind == "accepted" and &1.knowledge_item_id == corrected.accepted_item_id)
           )

    assert Enum.any?(
             outcomes,
             &(&1.kind == "contradicted" and &1.knowledge_item_id == accepted.accepted_item_id)
           )

    Repo.update_all(
      from(token in RetrievalToken, where: token.token_hash == ^sha256(capability.token)),
      set: [expires_at: DateTime.add(Cuckoding.Clock.wall_now(), -1, :second)]
    )

    assert {:error, :knowledge_capability_expired} =
             Knowledge.retrieve(capability.token, "durable rule",
               global_root: fixture.global_root
             )
  end

  test "a capability never retrieves another project's private item", %{root: root} do
    first = fixture(Path.join(root, "first"), false)
    candidate = extract(first, "Private build rule", "Only project one may read this.")

    assert {:ok, accepted} =
             Knowledge.review_candidate(candidate.id, "accepted", @actor, "Keep local")

    second = fixture(Path.join(root, "second"), false)
    next = next_run(second, "Private build rule")
    assert {:ok, capability} = Knowledge.issue_retrieval_token(next.run.id, next.attempt.id)
    assert {:ok, %{results: []}} = Knowledge.retrieve(capability.token, "private build rule")

    item = Repo.get!(Cuckoding.Knowledge.Item, accepted.accepted_item_id)

    assert {:error, :knowledge_scope_refused} =
             Knowledge.record_citations(next.run.id, next.attempt.id, [
               %{"id" => item.id, "version" => item.version}
             ])
  end

  defp fixture(root, global?) do
    suffix = System.unique_integer([:positive])
    repo = Path.join(root, "repo")
    workspace = Path.join(root, "workspace")
    File.mkdir_p!(repo)
    File.mkdir_p!(workspace)

    {:ok, project} =
      Projects.register(%{
        name: "Injection #{suffix}",
        repo_path: repo,
        default_branch: "main",
        workspace_root: workspace,
        port_range_start: 52_000,
        port_range_end: 52_100
      })

    policy_config = %{
      "version" => 1,
      "knowledge" => %{
        "auto_accept" => ["fact"],
        "global_retrieval_enabled" => global?
      }
    }

    {:ok, policy} =
      Projects.add_config_version(%{
        project_id: project.id,
        revision: 1,
        source_hash: sha256(Jason.encode!(policy_config)),
        config_json: policy_config,
        trusted_at: Cuckoding.Clock.wall_now()
      })

    {:ok, workflow} =
      Workflows.publish_workflow(%{
        project_id: project.id,
        name: "default",
        version: 1,
        definition_json: %{
          "stages" => [
            %{"key" => "implement", "role" => "implementer", "knowledge_triggers" => ["facts"]}
          ]
        },
        published_at: Cuckoding.Clock.wall_now()
      })

    {:ok, board} =
      Workflows.create_board(%{
        project_id: project.id,
        workflow_version_id: workflow.id,
        name: "Knowledge",
        concurrency_limit: 1
      })

    {:ok, task} =
      Workflows.create_task(%{board_id: board.id, title: "Produce knowledge", position: 0})

    {:ok, _command} = Workflows.transition_task(task.id, "ready", "fixture:#{task.id}:ready")
    run = create_run(task, policy, 1)
    attempt = create_attempt(run)
    create_session(attempt)
    {:ok, _command} = Execution.transition_run(run.id, "running", "fixture:#{run.id}:running")
    {:ok, _command} = Execution.transition_run(run.id, "done", "fixture:#{run.id}:done")

    %{
      project: project,
      policy: policy,
      board: board,
      run: Repo.reload!(run),
      repo: repo,
      root: root,
      global_root: Path.join(root, "global")
    }
  end

  defp next_run(fixture, title) do
    position = System.unique_integer([:positive])

    {:ok, task} =
      Workflows.create_task(%{board_id: fixture.board.id, title: title, position: position})

    {:ok, _command} = Workflows.transition_task(task.id, "ready", "next:#{task.id}:ready")
    run = create_run(task, fixture.policy, 1)
    attempt = create_attempt(run)
    create_session(attempt)
    run_dir = Path.join(fixture.root, "run-#{run.id}")
    File.mkdir_p!(Path.join(run_dir, "worktree"))
    %{run: run, task: task, attempt: attempt, run_dir: run_dir}
  end

  defp create_run(task, policy, sequence) do
    {:ok, run} =
      Execution.create_run(%{
        task_id: task.id,
        sequence: sequence,
        policy_snapshot_id: policy.id,
        branch: "feature/knowledge-#{String.slice(task.id, 0, 8)}",
        base_sha: String.duplicate("a", 40)
      })

    run
  end

  defp create_attempt(run) do
    {:ok, attempt} =
      Execution.create_stage_attempt(%{
        run_id: run.id,
        stage_key: "implement",
        attempt: 1,
        role_key: "implementer",
        role_kind: "agent"
      })

    attempt
  end

  defp create_session(attempt) do
    {:ok, session} =
      Execution.create_agent_session(%{
        stage_attempt_id: attempt.id,
        adapter_key: "fake",
        requested_model: "fixture",
        effective_grant_json: %{"requested" => %{}, "enforced" => %{}, "unenforced" => %{}}
      })

    session
  end

  defp extract(fixture, title, content) do
    assert {:ok, %{candidates: [candidate]}} =
             Knowledge.extract(fixture.run.id,
               adapter: FakeAdapter,
               adapter_options: [
                 reply: %{
                   "memory_operations" => [
                     %{
                       "kind" => "fact",
                       "title" => title,
                       "content" => content,
                       "confidence" => 0.9
                     }
                   ]
                 }
               ]
             )

    candidate
  end

  defp request(fixture, next) do
    %Types.StageRequest{
      project_id: fixture.project.id,
      board_id: fixture.board.id,
      task_id: next.task.id,
      run_id: next.run.id,
      stage_key: next.attempt.stage_key,
      attempt_id: next.attempt.id,
      objective: next.task.title,
      worktree_path: Path.join(next.run_dir, "worktree"),
      run_dir: next.run_dir,
      requested_model: "fixture",
      grant: %{"tools" => ["read"], "paths" => [Path.join(next.run_dir, "worktree")]},
      correlation_id: Cuckoding.Identifier.generate(),
      idempotency_key: "injection:#{next.attempt.id}"
    }
  end

  defp sha256(value), do: :crypto.hash(:sha256, value) |> Base.encode16(case: :lower)
end
