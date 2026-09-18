defmodule Cuckoding.Execution.CommandPolicyTest do
  use Cuckoding.DataCase, async: false

  alias Cuckoding.Execution
  alias Cuckoding.Execution.CommandPolicy
  alias Cuckoding.Execution.ProtectedPaths
  alias Cuckoding.Execution.RunEvent
  alias Cuckoding.Projects
  alias Cuckoding.Workflows
  alias Cuckoding.Workflows.Approval

  @now ~U[2026-09-17 22:00:00.000000Z]

  defmodule RecordingRunner do
    def exec(environment, command, options) do
      send(Keyword.fetch!(options, :caller), {:executed, environment.id, command})
      {:ok, %{exit_code: 0}}
    end
  end

  setup do
    root = Path.join(System.tmp_dir!(), "cuckoding-policy-#{System.unique_integer([:positive])}")
    fixture = Path.expand("../../fixtures/malicious_repository", __DIR__)
    File.cp_r!(fixture, root)
    git!(root, ["init", "-b", "main"])
    git!(root, ["config", "user.email", "fixture@example.test"])
    git!(root, ["config", "user.name", "Fixture"])
    git!(root, ["add", "--all"])
    git!(root, ["commit", "-m", "base"])

    run_dir = root <> "-run"
    File.mkdir_p!(run_dir)

    on_exit(fn ->
      File.rm_rf!(root)
      File.rm_rf!(run_dir)
    end)

    {:ok, loaded} = CommandPolicy.load_project(Path.join(root, ".cuckoding/project.yml"))
    base_sha = git!(root, ["rev-parse", "HEAD"])
    domain = domain_fixture(root, run_dir, base_sha, loaded)

    {:ok, root: root, run_dir: run_dir, loaded: loaded, domain: domain}
  end

  test "loads project.yml, classifies policy honestly, and executes only declared commands", %{
    loaded: loaded,
    domain: domain
  } do
    fields = CommandPolicy.classified_fields(loaded.config)

    assert Enum.any?(fields, &(&1.path == "commands" and &1.classification == :enforced))

    assert Enum.any?(
             fields,
             &(&1.path == "repository.protected_paths" and &1.classification == :enforced)
           )

    assert Enum.any?(
             fields,
             &(&1.path == "network.default_class" and &1.classification == :advisory)
           )

    assert Enum.any?(
             fields,
             &(&1.path == "resources.per_run.memory_mb_ceiling" and
                 &1.classification == :advisory)
           )

    assert {:ok, %{exit_code: 0}} =
             CommandPolicy.execute(domain.run, domain.environment, "test",
               runner: RecordingRunner,
               caller: self()
             )

    assert_receive {:executed, environment_id,
                    %{executable: "/usr/bin/printf", args: ["safe"], role: role}}

    assert environment_id == domain.environment.id
    assert role == "declared_command:test"

    assert {:error, {:command_not_declared, "release"}} =
             CommandPolicy.execute(domain.run, domain.environment, "release",
               runner: RecordingRunner,
               caller: self()
             )

    refute_received {:executed, _, %{role: "declared_command:release"}}
  end

  test "rejects traversal, absolute argument paths, shells, and invalid protected paths", %{
    root: root
  } do
    config_path = Path.join(root, "bad.yml")

    symlink_path = Path.join(root, "linked-project.yml")
    File.ln_s!(Path.join(root, ".cuckoding/project.yml"), symlink_path)
    assert {:error, :config_not_regular_file} = CommandPolicy.load_project(symlink_path)

    File.write!(config_path, """
    schema_version: 2
    repository:
      protected_paths: [../outside]
    commands:
      exfiltrate: [/bin/sh, -c, cat /etc/passwd]
    """)

    assert {:error, {"exfiltrate", :shell_commands_not_allowed}} =
             CommandPolicy.load_project(config_path)

    File.write!(config_path, """
    schema_version: 2
    repository:
      protected_paths: [/tmp]
    commands:
      exfiltrate: [/usr/bin/printf, ../../etc/passwd]
    """)

    assert {:error, {"exfiltrate", {:outside_worktree_path, "../../etc/passwd"}}} =
             CommandPolicy.load_project(config_path)

    File.write!(config_path, """
    schema_version: 2
    repository:
      protected_paths: [/tmp]
    commands:
      test: [/usr/bin/printf, safe]
    """)

    assert {:error, {:outside_worktree_path, "/tmp"}} =
             CommandPolicy.load_project(config_path)
  end

  test "commit and dirty protected changes require an exact human approval", %{
    root: root,
    domain: domain
  } do
    project_config = Path.join(root, ".cuckoding/project.yml")
    File.write!(project_config, File.read!(project_config) <> "\n# agent policy edit\n")
    git!(root, ["add", ".cuckoding/project.yml"])
    git!(root, ["commit", "-m", "edit protected config"])

    assert {:approval_required, first} =
             ProtectedPaths.gate_qa(domain.run, domain.attempt.id, domain.environment)

    assert first.protected_paths == [".cuckoding/project.yml"]
    assert first.approval.decision == "pending"
    assert String.starts_with?(first.approval.kind, "protected_path_change:")

    assert {:approval_required, repeated} =
             ProtectedPaths.gate_qa(domain.run, domain.attempt.id, domain.environment)

    assert repeated.approval.id == first.approval.id
    assert Repo.aggregate(Approval, :count) == 1

    assert {:ok, %{decision: "approved", actor: "qa-user"}} =
             Workflows.decide_approval(first.approval.id, "approved", "qa-user", "Reviewed diff")

    assert {:ok, approved} =
             ProtectedPaths.gate_qa(domain.run, domain.attempt.id, domain.environment)

    assert approved.approval.id == first.approval.id

    workflow = Path.join(root, ".github/workflows/ci.yml")
    File.write!(workflow, File.read!(workflow) <> "\n# second protected edit\n")

    assert {:approval_required, second} =
             ProtectedPaths.gate_qa(domain.run, domain.attempt.id, domain.environment)

    assert second.approval.id != first.approval.id
    assert second.protected_paths == [".cuckoding/project.yml", ".github/workflows/ci.yml"]
    assert Repo.aggregate(Approval, :count) == 2

    assert {:ok, %{decision: "rejected"}} =
             Workflows.decide_approval(second.approval.id, "rejected", "qa-user", "Unsafe")

    assert {:approval_rejected, rejected} =
             ProtectedPaths.gate_qa(domain.run, domain.attempt.id, domain.environment)

    assert rejected.approval.id == second.approval.id

    event_types =
      Repo.all(
        from(event in RunEvent,
          where: event.run_id == ^domain.run.id,
          order_by: event.sequence,
          select: event.event_type
        )
      )

    assert event_types == [
             "policy.protected_paths_flagged",
             "approval.decided",
             "policy.protected_paths_flagged",
             "approval.decided"
           ]
  end

  test "renaming a protected file still flags its old path", %{root: root, domain: domain} do
    git!(root, ["mv", ".github/workflows/ci.yml", "ci.yml"])

    assert {:ok, paths} =
             ProtectedPaths.scan(domain.environment, [".github/workflows"])

    assert paths == [".github/workflows/ci.yml"]
  end

  defp domain_fixture(root, run_dir, base_sha, loaded) do
    suffix = System.unique_integer([:positive])

    {:ok, project} =
      Projects.register(%{
        name: "Policy project #{suffix}",
        repo_path: root,
        default_branch: "main",
        workspace_root: Path.dirname(root),
        port_range_start: 43_000,
        port_range_end: 43_100
      })

    {:ok, policy} =
      Projects.add_config_version(%{
        project_id: project.id,
        revision: 1,
        source_hash: loaded.source_hash,
        config_json: loaded.config,
        trusted_at: @now
      })

    {:ok, workflow} =
      Workflows.publish_workflow(%{
        project_id: project.id,
        name: "default",
        version: 1,
        definition_json: %{"stages" => [%{"key" => "implementation", "role" => "implementer"}]},
        published_at: @now
      })

    {:ok, board} =
      Workflows.create_board(%{
        project_id: project.id,
        workflow_version_id: workflow.id,
        name: "Board",
        concurrency_limit: 1
      })

    {:ok, task} = Workflows.create_task(%{board_id: board.id, title: "Task", position: 1})

    {:ok, run} =
      Execution.create_run(%{
        task_id: task.id,
        sequence: 1,
        policy_snapshot_id: policy.id,
        plugin_snapshot_json: %{},
        branch: "feature/policy-#{suffix}",
        base_sha: base_sha
      })

    {:ok, attempt} =
      Execution.create_stage_attempt(%{
        run_id: run.id,
        stage_key: "qa",
        attempt: 1,
        role_key: "qa",
        role_kind: "system"
      })

    {:ok, environment} =
      Execution.create_environment(%{
        run_id: run.id,
        runner_key: "local_process",
        kind: "local_process",
        worktree_path: root,
        run_dir: run_dir,
        base_sha: base_sha,
        head_sha: base_sha,
        ports_json: %{},
        isolation_claims_json: %{"sandbox" => false}
      })

    %{run: run, attempt: attempt, environment: environment}
  end

  defp git!(root, args) do
    case System.cmd("/usr/bin/git", ["-C", root | args], stderr_to_stdout: true) do
      {output, 0} -> String.trim(output)
      {output, status} -> raise "git failed (#{status}): #{output}"
    end
  end
end
