defmodule Cuckoding.Execution.GitServiceTest do
  use Cuckoding.DataCase, async: false

  alias Cuckoding.Execution
  alias Cuckoding.Execution.GitRecoveryInspector
  alias Cuckoding.Execution.GitService
  alias Cuckoding.Execution.Reconciler
  alias Cuckoding.Execution.Run
  alias Cuckoding.Projects
  alias Cuckoding.Repo
  alias Cuckoding.Workflows

  @git "/usr/bin/git"
  @now ~U[2026-09-17 21:30:00.000000Z]

  setup do
    root =
      Path.join(System.tmp_dir!(), "cuckoding-git-service-#{System.unique_integer([:positive])}")

    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)

    bare = Path.join(root, "remote.git")
    seed = Path.join(root, "seed")
    repo = Path.join(root, "repo")
    workspace = Path.join(root, "workspaces")

    git!(root, ["init", "--bare", bare])
    git!(root, ["init", "-b", "main", seed])
    configure_identity!(seed)
    File.write!(Path.join(seed, "README.md"), "# fixture\n")
    git!(seed, ["add", "README.md"])
    git!(seed, ["commit", "-m", "initial"])
    git!(seed, ["remote", "add", "origin", bare])
    git!(seed, ["push", "-u", "origin", "main"])
    git!(bare, ["symbolic-ref", "HEAD", "refs/heads/main"])
    git!(root, ["clone", bare, repo])
    configure_identity!(repo)

    domain = domain_fixture(repo, workspace)

    {:ok, Map.merge(domain, %{root: root, bare: bare, repo: repo, workspace: workspace})}
  end

  test "creates a confined worktree from the captured SHA and detects drift", fixture do
    assert git!(fixture.repo, ["remote", "get-url", "origin"]) == fixture.bare
    assert {:ok, base_sha} = GitService.capture_base(fixture.project)
    run = run_fixture(fixture, "feature/one", base_sha)

    assert {:ok, environment} = GitService.prepare(fixture.project, run)
    assert environment.base_sha == base_sha
    assert environment.head_sha == base_sha

    assert Path.dirname(environment.run_dir) ==
             Path.join(canonical_directory(fixture.workspace), fixture.project.id)

    assert environment.worktree_path == Path.join(environment.run_dir, "worktree")
    assert {:ok, %{clean?: true, head_sha: ^base_sha}} = GitService.inspect(environment)

    marker = environment.run_dir |> Path.join("run.json") |> File.read!() |> Jason.decode!()
    assert marker["project_id"] == fixture.project.id
    assert marker["board_id"] == fixture.board.id
    assert marker["task_id"] == run.task_id
    assert marker["run_id"] == run.id
    assert marker["policy_hash"] == fixture.policy.source_hash

    File.write!(Path.join(environment.worktree_path, "change.txt"), "changed\n")
    git!(environment.worktree_path, ["add", "change.txt"])
    git!(environment.worktree_path, ["commit", "-m", "change"])

    assert {:drift, :head_changed} = GitService.inspect(environment)

    assert {:ok, %{decisions: [{:ok, command}]}} =
             Reconciler.run(
               inspector: GitRecoveryInspector,
               cycle_id: "git-drift",
               run_ids: [run.id]
             )

    assert command.result["outcome"] == "block"
    assert command.result["reasons"] == ["worktree_drift"]
    assert Repo.get!(Run, run.id).state == "blocked"
  end

  test "reports dirty status without inventing revision drift", fixture do
    {:ok, base_sha} = GitService.capture_base(fixture.project)
    run = run_fixture(fixture, "feature/dirty-worktree", base_sha)
    {:ok, environment} = GitService.prepare(fixture.project, run)
    marker_path = Path.join(environment.run_dir, "run.json")
    marker = File.read!(marker_path)

    File.write!(Path.join(environment.worktree_path, "untracked.txt"), "dirty\n")

    assert {:ok, %{clean?: false, head_sha: ^base_sha}} = GitService.inspect(environment)

    File.write!(marker_path, "{}")
    assert {:drift, :ownership_marker_changed} = GitService.inspect(environment)
    File.write!(marker_path, marker)
  end

  test "blocks inspection when the recorded base branch has moved", fixture do
    {:ok, base_sha} = GitService.capture_base(fixture.project)
    run = run_fixture(fixture, "feature/base-drift", base_sha)
    {:ok, environment} = GitService.prepare(fixture.project, run)

    File.write!(Path.join(fixture.repo, "base-change.txt"), "changed\n")
    git!(fixture.repo, ["add", "base-change.txt"])
    git!(fixture.repo, ["commit", "-m", "move base"])

    assert {:drift, :base_changed} = GitService.inspect(environment)

    stale_run = run_fixture(fixture, "feature/stale-base", base_sha)
    assert {:error, :base_changed} = GitService.prepare(fixture.project, stale_run)
  end

  test "rejects dirty bases and protected target branches", fixture do
    {:ok, base_sha} = GitService.capture_base(fixture.project)
    dirty_run = run_fixture(fixture, "feature/dirty-base", base_sha)
    File.write!(Path.join(fixture.repo, "README.md"), "dirty\n")

    assert {:error, :dirty_repository} = GitService.capture_base(fixture.project)
    assert {:error, :dirty_repository} = GitService.prepare(fixture.project, dirty_run)

    git!(fixture.repo, ["restore", "README.md"])
    protected_run = run_fixture(fixture, "main", base_sha)
    assert {:error, :protected_branch} = GitService.prepare(fixture.project, protected_run)
  end

  test "rejects traversal identifiers and symlink escapes", fixture do
    {:ok, base_sha} = GitService.capture_base(fixture.project)
    traversal_run = run_fixture(fixture, "feature/traversal", base_sha)

    assert {:error, :invalid_identifier} =
             GitService.prepare(%{fixture.project | id: "../escape"}, traversal_run)

    symlink_run = run_fixture(fixture, "feature/symlink", base_sha)
    outside = Path.join(fixture.root, "outside")
    File.mkdir_p!(outside)
    File.mkdir_p!(fixture.workspace)
    File.ln_s!(outside, Path.join(fixture.workspace, fixture.project.id))

    assert {:error, :symlink_component} = GitService.prepare(fixture.project, symlink_run)
    refute File.exists?(Path.join(outside, symlink_run.id))
  end

  test "candidate commits reject paths outside the owned worktree and symlinks", fixture do
    {:ok, base_sha} = GitService.capture_base(fixture.project)
    run = run_fixture(fixture, "feature/candidate-paths", base_sha)
    {:ok, environment} = GitService.prepare(fixture.project, run)
    File.write!(Path.join(environment.worktree_path, "change.txt"), "change\n")

    assert {:error, :candidate_path_escape} =
             GitService.commit_candidate(environment, ["../change.txt"], "candidate")

    outside = Path.join(fixture.root, "outside.txt")
    File.write!(outside, "outside\n")
    File.ln_s!(outside, Path.join(environment.worktree_path, "linked.txt"))

    assert {:error, :candidate_path_symlink} =
             GitService.commit_candidate(environment, ["linked.txt"], "candidate")
  end

  test "distinct runs cannot share a branch or worktree", fixture do
    {:ok, base_sha} = GitService.capture_base(fixture.project)
    first = run_fixture(fixture, "feature/shared", base_sha)
    second = run_fixture(fixture, "feature/shared", base_sha)
    third = run_fixture(fixture, "feature/third", base_sha)

    assert {:ok, first_environment} = GitService.prepare(fixture.project, first)

    assert {:error, :branch_exists} = GitService.prepare(fixture.project, second)

    refute File.exists?(
             Path.join([canonical_directory(fixture.workspace), fixture.project.id, second.id])
           )

    assert {:ok, third_environment} = GitService.prepare(fixture.project, third)

    refute first_environment.worktree_path == third_environment.worktree_path
    assert Repo.aggregate(Execution.Environment, :count, :id) == 2
  end

  defp domain_fixture(repo, workspace) do
    suffix = System.unique_integer([:positive])

    {:ok, project} =
      Projects.register(%{
        name: "Git project #{suffix}",
        repo_path: repo,
        default_branch: "main",
        workspace_root: workspace,
        port_range_start: 42_000,
        port_range_end: 42_100
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
        definition_json: %{"stages" => []},
        published_at: @now
      })

    {:ok, board} =
      Workflows.create_board(%{
        project_id: project.id,
        workflow_version_id: workflow.id,
        name: "Board",
        concurrency_limit: 4
      })

    %{project: project, policy: policy, workflow: workflow, board: board}
  end

  defp run_fixture(fixture, branch, base_sha) do
    {:ok, run} = run_result(fixture, branch, base_sha)
    run
  end

  defp run_result(fixture, branch, base_sha) do
    position = System.unique_integer([:positive])

    {:ok, task} =
      Workflows.create_task(%{
        board_id: fixture.board.id,
        title: "Task #{position}",
        position: position
      })

    Execution.create_run(%{
      task_id: task.id,
      sequence: 1,
      policy_snapshot_id: fixture.policy.id,
      plugin_snapshot_json: %{},
      branch: branch,
      base_sha: base_sha
    })
  end

  defp configure_identity!(repo) do
    git!(repo, ["config", "user.name", "Cuckoding Test"])
    git!(repo, ["config", "user.email", "cuckoding@example.invalid"])
  end

  defp git!(directory, args) do
    case System.cmd(@git, args, cd: directory, stderr_to_stdout: true) do
      {output, 0} -> String.trim(output)
      {output, status} -> flunk("git #{Enum.join(args, " ")} failed (#{status}): #{output}")
    end
  end

  defp canonical_directory(path) do
    {resolved, 0} = System.cmd("/bin/pwd", ["-P"], cd: path)
    String.trim(resolved)
  end
end
