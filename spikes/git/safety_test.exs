ExUnit.start()

# Executable experiment, not a production Git API.
defmodule BossGitSpike do
  def open_task(repo, path, branch, base) do
    with :ok <- commit_sha(repo, base),
         {:ok, _} <- git(repo, ["check-ref-format", "refs/heads/#{branch}"]),
         {:ok, _} <- ensure_task(repo, path, branch, base),
         :ok <- same_repository(repo, path),
         :ok <- equals(path, ["symbolic-ref", "HEAD"], "refs/heads/#{branch}", :identity_mismatch),
         :ok <- ancestor(path, base, "HEAD", :base_mismatch) do
      git(path, ["rev-parse", "HEAD"])
    end
  end

  def prepare(repo, path, target, expected, task) do
    with :ok <- commit_sha(repo, expected),
         :ok <- commit_sha(repo, task),
         :ok <- target_at(repo, target, expected),
         {:ok, _} <- git(repo, ["worktree", "add", "--detach", path, expected]),
         {:ok, _} <- git(path, ["merge", "--no-ff", "--no-edit", task]),
         :ok <- clean(path) do
      git(path, ["rev-parse", "HEAD"])
    end
  end

  def publish(repo, path, target, expected, candidate_path, checked) do
    with :ok <- commit_sha(repo, expected),
         :ok <- commit_sha(repo, checked),
         :ok <- same_repository(repo, candidate_path),
         :ok <- clean(candidate_path),
         :ok <- equals(candidate_path, ["rev-parse", "HEAD"], checked, :candidate_drift),
         :ok <- ancestor(repo, expected, checked, :base_mismatch),
         :ok <- target_at(repo, target, expected),
         # Git's checkout guard is part of the policy. Never add --force here.
         {:ok, _} <- git(repo, ["worktree", "add", path, target]),
         :ok <- equals(path, ["rev-parse", "HEAD"], expected, :target_drift),
         :ok <- clean(path),
         {:ok, _} <- git(path, ["merge", "--ff-only", checked]),
         :ok <- equals(path, ["rev-parse", "HEAD"], checked, :target_drift) do
      {:ok, checked}
    end
  end

  def cleanup(repo, path, integrated) do
    with :ok <- commit_sha(repo, integrated),
         :ok <- same_repository(repo, path),
         :ok <- clean(path),
         :ok <- ancestor(path, "HEAD", integrated, :unmerged),
         {:ok, _} <- git(repo, ["worktree", "remove", path]) do
      :ok
    end
  end

  defp ensure_task(repo, path, branch, base) do
    if File.exists?(path),
      do: {:ok, :existing},
      else: git(repo, ["worktree", "add", "-b", branch, path, base])
  end

  defp commit_sha(repo, sha) do
    if Regex.match?(~r/\A(?:[0-9a-f]{40}|[0-9a-f]{64})\z/, sha),
      do: equals(repo, ["rev-parse", "--verify", "#{sha}^{commit}"], sha, :not_commit),
      else: {:error, :full_sha_required}
  end

  defp target_at(repo, target, expected) do
    with {:ok, _} <- git(repo, ["check-ref-format", "refs/heads/#{target}"]) do
      equals(repo, ["rev-parse", "--verify", "refs/heads/#{target}"], expected, :target_drift)
    end
  end

  defp same_repository(repo, path) do
    args = ["rev-parse", "--path-format=absolute", "--git-common-dir"]
    with {:ok, common} <- git(repo, args), do: equals(path, args, common, :identity_mismatch)
  end

  defp clean(path) do
    equals(path, ["status", "--porcelain=v1", "--untracked-files=all", "--ignored"], "", :dirty)
  end

  defp equals(repo, args, expected, reason) do
    case git(repo, args) do
      {:ok, ^expected} -> :ok
      {:ok, _} -> {:error, reason}
      error -> error
    end
  end

  defp ancestor(repo, base, head, reason) do
    case git(repo, ["merge-base", "--is-ancestor", base, head]) do
      {:ok, _} -> :ok
      {:error, {:git, _, 1, _}} -> {:error, reason}
      error -> error
    end
  end

  def git(repo, args) do
    # Keep inherited Git settings from redirecting scratch operations to user data.
    env = for {key, _} <- System.get_env(), String.starts_with?(key, "GIT_"), do: {key, nil}
    env = env ++ [{"GIT_CONFIG_GLOBAL", "/dev/null"}, {"GIT_CONFIG_NOSYSTEM", "1"}]

    case System.cmd("git", ["-C", repo | args], stderr_to_stdout: true, env: env) do
      {output, 0} -> {:ok, String.trim(output)}
      {output, status} -> {:error, {:git, args, status, String.trim(output)}}
    end
  end
end

defmodule BossGitSpikeTest do
  use ExUnit.Case, async: false
  alias BossGitSpike, as: Spike

  setup do
    root = Path.join(System.tmp_dir!(), "boss-git-#{System.unique_integer([:positive])}")
    repo = Path.join(root, "source with spaces")
    File.mkdir_p!(repo)
    git!(repo, ["init", "--initial-branch=main"])
    git!(repo, ["config", "user.name", "BOSS spike"])
    git!(repo, ["config", "user.email", "spike@example.invalid"])
    git!(repo, ["config", "commit.gpgSign", "false"])
    git!(repo, ["config", "core.hooksPath", Path.join(root, "no-hooks")])
    File.write!(Path.join(repo, ".gitignore"), "ignored.txt\n")
    base = commit(repo, "shared.txt", "base\n")
    # This root is created exclusively by this test; never a user/project path.
    on_exit(fn -> File.rm_rf!(root) end)
    {:ok, root: root, repo: repo, base: base}
  end

  test "two tasks use the pinned commit and preserve dirty source files", c do
    commit(c.repo, "later.txt", "later target\n")
    File.write!(Path.join(c.repo, "shared.txt"), "user edits\n")
    File.write!(Path.join(c.repo, "untracked.txt"), "user notes\n")
    before = snapshot(c.repo)
    first = Path.join(c.root, "first ; literal")
    second = Path.join(c.root, "second")
    assert {:ok, base} = Spike.open_task(c.repo, first, "codex/first", c.base)
    assert base == c.base
    assert {:ok, ^base} = Spike.open_task(c.repo, second, "codex/second", c.base)
    commit(first, "first.txt", "only first\n")
    refute File.exists?(Path.join(second, "first.txt"))
    refute File.exists?(Path.join(first, "later.txt"))
    assert snapshot(c.repo) == before
  end

  test "reopening preserves commits and edits, refusing mismatched identity", c do
    path = task(c)
    head = commit(path, "task.txt", "committed\n")
    File.write!(Path.join(path, "shared.txt"), "unfinished\n")
    before = snapshot(path)
    assert {:ok, ^head} = Spike.open_task(c.repo, path, "codex/task", c.base)
    assert {:error, :identity_mismatch} = Spike.open_task(c.repo, path, "codex/other", c.base)
    future = commit(c.repo, "later.txt", "later\n")
    assert {:error, :base_mismatch} = Spike.open_task(c.repo, path, "codex/task", future)
    assert snapshot(path) == before
  end

  test "a branch name is not a pinned base", c do
    path = Path.join(c.root, "invalid")
    assert {:error, :full_sha_required} = Spike.open_task(c.repo, path, "codex/task", "main")
    refute File.exists?(path)
  end

  test "cleanup preserves tracked, untracked and ignored files", c do
    for name <- ["shared.txt", "new.txt", "ignored.txt"] do
      path = Path.join(c.root, name)
      assert {:ok, _} = Spike.open_task(c.repo, path, "codex/#{name}", c.base)
      File.write!(Path.join(path, name), "must survive\n")
      assert {:error, :dirty} = Spike.cleanup(c.repo, path, c.base)
      assert File.read!(Path.join(path, name)) == "must survive\n"
    end
  end

  test "cleanup refuses clean unmerged commits and removes a proven integrated tree", c do
    path = task(c)
    head = commit(path, "task.txt", "keep commit\n")
    assert {:error, :unmerged} = Spike.cleanup(c.repo, path, c.base)
    assert git!(path, ["rev-parse", "HEAD"]) == head
    git!(c.repo, ["merge", "--ff-only", head])
    assert :ok = Spike.cleanup(c.repo, path, head)
    refute File.exists?(path)
    assert git!(c.repo, ["rev-parse", "codex/task"]) == head
  end

  test "merge conflicts preserve the failed integration worktree and target", c do
    path = task(c)
    task_head = commit(path, "shared.txt", "task version\n")
    expected = commit(c.repo, "shared.txt", "target version\n")
    before = snapshot(c.repo)
    integration = Path.join(c.root, "integration")

    assert {:error, {:git, ["merge" | _], _, _}} =
             Spike.prepare(c.repo, integration, "main", expected, task_head)

    assert git!(integration, ["diff", "--name-only", "--diff-filter=U"]) == "shared.txt"
    assert File.exists?(Path.join(integration, "shared.txt"))
    assert snapshot(c.repo) == before
  end

  test "target drift before preparation refuses without creating a worktree", c do
    path = task(c)
    head = commit(path, "task.txt", "task\n")
    commit(c.repo, "target.txt", "target advanced\n")
    before = snapshot(c.repo)
    integration = Path.join(c.root, "integration")
    assert {:error, :target_drift} = Spike.prepare(c.repo, integration, "main", c.base, head)
    refute File.exists?(integration)
    assert snapshot(c.repo) == before
  end

  test "publication refuses a target checked out in the source directory", c do
    {integration, candidate} = candidate(c)
    before = snapshot(c.repo)
    publication = Path.join(c.root, "publication")

    assert {:error, {:git, ["worktree", "add" | _], _, _}} =
             Spike.publish(c.repo, publication, "main", c.base, integration, candidate)

    assert snapshot(c.repo) == before
    assert git!(integration, ["rev-parse", "HEAD"]) == candidate
    refute File.exists?(publication)
  end

  test "publication also refuses a target checked out in another linked tree", c do
    {integration, candidate} = candidate(c)
    git!(c.repo, ["switch", "--detach"])
    other = Path.join(c.root, "user-other")
    git!(c.repo, ["worktree", "add", other, "main"])
    before = snapshot(other)

    assert {:error, {:git, ["worktree", "add" | _], _, _}} =
             Spike.publish(
               c.repo,
               Path.join(c.root, "publication"),
               "main",
               c.base,
               integration,
               candidate
             )

    assert snapshot(other) == before
  end

  test "publication fast-forwards only its owned checkout; source stays unchanged", c do
    {integration, candidate} = candidate(c)
    git!(c.repo, ["switch", "--detach"])
    File.write!(Path.join(c.repo, "shared.txt"), "user edits while detached\n")
    before = snapshot(c.repo)
    publication = Path.join(c.root, "publication")

    assert {:ok, ^candidate} =
             Spike.publish(c.repo, publication, "main", c.base, integration, candidate)

    assert git!(publication, ["rev-parse", "HEAD"]) == candidate
    assert git!(publication, ["symbolic-ref", "HEAD"]) == "refs/heads/main"
    assert git!(c.repo, ["rev-parse", "refs/heads/main"]) == candidate
    assert File.read!(Path.join(publication, "task.txt")) == "task\n"
    assert snapshot(c.repo) == before
  end

  test "target advancement after candidate checks blocks publication", c do
    {integration, candidate} = candidate(c)
    advanced = commit(c.repo, "target.txt", "new target\n")
    git!(c.repo, ["switch", "--detach"])
    before = snapshot(c.repo)

    assert {:error, :target_drift} =
             Spike.publish(
               c.repo,
               Path.join(c.root, "publication"),
               "main",
               c.base,
               integration,
               candidate
             )

    assert git!(c.repo, ["rev-parse", "refs/heads/main"]) == advanced
    assert snapshot(c.repo) == before
  end

  test "candidate edits and changed HEAD invalidate previous checked SHA", c do
    {integration, candidate} = candidate(c)
    git!(c.repo, ["switch", "--detach"])
    publication = Path.join(c.root, "publication")
    File.write!(Path.join(integration, "unchecked.txt"), "new content\n")

    assert {:error, :dirty} =
             Spike.publish(c.repo, publication, "main", c.base, integration, candidate)

    commit(integration, "unchecked.txt", "new content\n")

    assert {:error, :candidate_drift} =
             Spike.publish(c.repo, publication, "main", c.base, integration, candidate)

    assert git!(c.repo, ["rev-parse", "refs/heads/main"]) == c.base
    refute File.exists?(publication)
  end

  defp task(c) do
    path = Path.join(c.root, "task")
    assert {:ok, _} = Spike.open_task(c.repo, path, "codex/task", c.base)
    path
  end

  defp candidate(c) do
    path = task(c)
    head = commit(path, "task.txt", "task\n")
    integration = Path.join(c.root, "integration")
    assert {:ok, candidate} = Spike.prepare(c.repo, integration, "main", c.base, head)
    {integration, candidate}
  end

  defp commit(repo, name, contents) do
    File.write!(Path.join(repo, name), contents)
    git!(repo, ["add", "--all"])
    git!(repo, ["commit", "-m", "spike fixture"])
    git!(repo, ["rev-parse", "HEAD"])
  end

  defp snapshot(repo) do
    {git!(repo, ["rev-parse", "HEAD"]),
     git!(repo, ["status", "--porcelain=v1", "--untracked-files=all", "--ignored"]),
     git!(repo, ["diff", "--binary", "HEAD"]),
     for(name <- ["shared.txt", "untracked.txt"], do: File.read(Path.join(repo, name)))}
  end

  defp git!(repo, args) do
    assert {:ok, output} = Spike.git(repo, args)
    output
  end
end
