defmodule Boss.Deliveries.IntegrationTest do
  use ExUnit.Case, async: false
  alias Boss.Agents.Workspace
  alias Boss.Checks.Candidate
  alias Boss.Deliveries.Integration
  @moduletag skip: :os.type() != {:unix, :darwin}

  setup tags do
    root = Path.join(System.tmp_dir!(), "boss-integration-#{Ecto.UUID.generate()}")
    File.mkdir!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    {physical, 0} = System.cmd("/bin/pwd", ["-P"], cd: root)
    root = String.trim(physical)
    source = Path.join(root, "source")
    data = Path.join(root, "data")
    File.mkdir!(source)
    File.mkdir!(data)

    git!(
      source,
      ["init", "-b", "main"] ++ if(tags[:sha256], do: ["--object-format=sha256"], else: [])
    )

    git!(source, ["config", "user.name", "Fixture"])
    git!(source, ["config", "user.email", "fixture@example.invalid"])
    File.write!(Path.join(source, "tracked.txt"), "base")
    git!(source, ["add", "."])
    git!(source, ["commit", "-m", "base"])
    base = git!(source, ["rev-parse", "HEAD"])

    project = %{
      id: 1,
      root_path: source,
      git_common_dir: Path.join(source, ".git"),
      base_branch: "main"
    }

    opts = [data_dir: data]
    {:ok, run} = Workspace.plan(project, Ecto.UUID.generate(), opts)
    {:ok, _} = Workspace.prepare(run, opts)
    File.write!(Path.join(run.path, "tracked.txt"), "reviewed")
    {:ok, candidate} = Candidate.plan(run, Ecto.UUID.generate(), opts)
    {:ok, %{candidate_commit: sha}} = Candidate.prepare(candidate, opts)
    {:ok, intent} = Integration.plan(project, Ecto.UUID.generate(), candidate, sha, base, opts)

    %{
      root: root,
      source: source,
      project: project,
      run: run,
      candidate: candidate,
      sha: sha,
      base: base,
      intent: intent,
      opts: opts
    }
  end

  test "exact publication reserves the target and preserves dirty user checkout and source index",
       c do
    git!(c.source, ["switch", "-c", "user-work"])
    File.write!(Path.join(c.source, "tracked.txt"), "staged user changes")
    git!(c.source, ["add", "tracked.txt"])
    File.write!(Path.join(c.source, "tracked.txt"), "unstaged user changes")
    File.write!(Path.join(c.source, "untracked.txt"), "private")
    index = File.read!(Path.join(c.source, ".git/index"))
    assert :ok = Integration.prepare(c.intent, c.opts)
    assert git!(c.intent["path"], ["symbolic-ref", "HEAD"]) == "refs/heads/main"
    assert {:error, :integration_exists} = Integration.prepare(c.intent, c.opts)
    assert {:ok, c.sha} == Integration.publish(c.intent, c.opts)
    assert :ok = Integration.verify_published(c.intent, c.opts)
    assert git!(c.source, ["rev-parse", "main"]) == c.sha
    assert git!(c.source, ["rev-parse", "HEAD"]) == c.base
    assert git!(c.source, ["symbolic-ref", "HEAD"]) == "refs/heads/user-work"
    assert File.read!(Path.join(c.source, ".git/index")) == index
    assert File.read!(Path.join(c.source, "tracked.txt")) == "unstaged user changes"
    assert File.read!(Path.join(c.source, "untracked.txt")) == "private"
    assert File.read!(Path.join(c.run.path, "tracked.txt")) == "reviewed"
    assert File.read!(Path.join(c.intent["path"], "tracked.txt")) == "reviewed"
    assert :ok = Integration.release(c.intent, c.opts)

    assert {:error, {:git_exit, 1}} =
             Workspace.git(c.intent["path"], ["symbolic-ref", "-q", "HEAD"])

    assert :ok = Integration.verify_published(c.intent, c.opts)
    assert File.read!(Path.join(c.source, ".git/index")) == index
    assert File.read!(Path.join(c.source, "tracked.txt")) == "unstaged user changes"
    assert File.read!(Path.join(c.intent["path"], "tracked.txt")) == "reviewed"
    git!(c.source, ["worktree", "add", Path.join(c.root, "next-owner"), "main"])
    assert :ok = Integration.verify_published(c.intent, c.opts)
  end

  test "checked-out target is refused in the source or any other worktree", c do
    assert {:error, :target_checked_out} = Integration.prepare(c.intent, c.opts)
    refute File.exists?(c.intent["path"])
    git!(c.source, ["switch", "--detach"])
    other = Path.join(c.root, "other")
    git!(c.source, ["worktree", "add", other, "main"])
    assert {:error, :target_checked_out} = Integration.prepare(c.intent, c.opts)
    refute File.exists?(c.intent["path"])
  end

  test "target drift at final CAS is rejected without overwriting the changed target", c do
    ready!(c)
    other = git!(c.source, ["commit-tree", "#{c.base}^{tree}", "-p", c.base, "-m", "concurrent"])

    runner = fn executable, args, options ->
      if "update-ref" in args,
        do: git!(c.source, ["update-ref", "refs/heads/main", other, c.base])

      Boss.Agents.Process.run(executable, args, options)
    end

    assert {:error, :target_changed} =
             Integration.publish(c.intent, Keyword.put(c.opts, :runner, runner))

    assert git!(c.source, ["rev-parse", "main"]) == other
    assert File.read!(Path.join(c.intent["path"], "tracked.txt")) == "base"
  end

  test "symbolic target and symlink ref aliases are refused", c do
    git!(c.source, ["switch", "--detach"])
    git!(c.source, ["branch", "other", c.base])
    git!(c.source, ["symbolic-ref", "refs/heads/main", "refs/heads/other"])
    assert {:error, :target_changed} = Integration.prepare(c.intent, c.opts)
    refute File.exists?(c.intent["path"])
    File.rm!(Path.join(c.source, ".git/refs/heads/main"))
    File.ln_s!("other", Path.join(c.source, ".git/refs/heads/main"))
    assert {:error, :target_changed} = Integration.prepare(c.intent, c.opts)
    assert git!(c.source, ["rev-parse", "other"]) == c.base
  end

  test "changed candidate, hidden candidate edits and hidden publication edits block publication",
       c do
    ready!(c)
    git!(c.candidate["path"], ["update-index", "--assume-unchanged", "tracked.txt"])
    File.write!(Path.join(c.candidate["path"], "tracked.txt"), "hidden candidate change")
    assert {:error, :candidate_changed} = Integration.publish(c.intent, c.opts)
    File.write!(Path.join(c.candidate["path"], "tracked.txt"), "reviewed")
    git!(c.intent["path"], ["update-index", "--skip-worktree", "tracked.txt"])
    File.write!(Path.join(c.intent["path"], "tracked.txt"), "hidden publication change")
    assert {:error, :candidate_changed} = Integration.publish(c.intent, c.opts)
    assert git!(c.source, ["rev-parse", "main"]) == c.base
  end

  test "forged paths, common directory and linked worktree metadata fail closed", c do
    git!(c.source, ["switch", "--detach"])

    assert {:error, :invalid_integration} =
             Integration.prepare(%{c.intent | "path" => c.source}, c.opts)

    assert {:error, :invalid_integration} =
             Integration.prepare(%{c.intent | "git_common_dir" => c.root}, c.opts)

    assert :ok = Integration.prepare(c.intent, c.opts)
    gitfile = Path.join(c.intent["path"], ".git")
    File.rm!(gitfile)
    File.ln_s!(Path.join(c.candidate["path"], ".git"), gitfile)
    assert {:error, :integration_path} = Integration.publish(c.intent, c.opts)
    assert git!(c.source, ["rev-parse", "main"]) == c.base
  end

  test "an existing integration directory is retained without adopting or removing it", c do
    git!(c.source, ["switch", "--detach"])
    File.mkdir_p!(c.intent["path"])
    File.write!(Path.join(c.intent["path"], "keep.txt"), "keep")
    assert {:error, :integration_exists} = Integration.prepare(c.intent, c.opts)
    assert File.read!(Path.join(c.intent["path"], "keep.txt")) == "keep"
  end

  test "mutation after publication invalidates integration evidence", c do
    ready!(c)
    assert {:ok, c.sha} == Integration.publish(c.intent, c.opts)
    File.write!(Path.join(c.intent["path"], "tracked.txt"), "check mutated files")
    assert {:error, :candidate_changed} = Integration.verify_published(c.intent, c.opts)
    assert {:error, :candidate_changed} = Integration.release(c.intent, c.opts)
    assert git!(c.intent["path"], ["symbolic-ref", "HEAD"]) == "refs/heads/main"
    assert git!(c.source, ["rev-parse", "main"]) == c.sha
  end

  test "publication still requires the reserved target to be attached", c do
    ready!(c)
    git!(c.intent["path"], ["switch", "--detach", c.base])
    assert {:error, :integration_changed} = Integration.publish(c.intent, c.opts)
    assert git!(c.source, ["rev-parse", "main"]) == c.base
  end

  test "unknown CAS outcome retains the target without rollback", c do
    ready!(c)

    runner = fn executable, args, options ->
      result = Boss.Agents.Process.run(executable, args, options)
      if "update-ref" in args, do: %{cleanup: :unknown, outcome: :failed}, else: result
    end

    assert {:error, :publication_unknown} =
             Integration.publish(c.intent, Keyword.put(c.opts, :runner, runner))

    assert git!(c.source, ["rev-parse", "main"]) == c.sha
    assert File.exists?(c.intent["path"])
    assert File.read!(Path.join(c.intent["path"], "tracked.txt")) == "base"
  end

  test "failure to populate the owned checkout after CAS is an unknown publication", c do
    ready!(c)

    runner = fn executable, args, options ->
      if "read-tree" in args and "--reset" in args do
        %{cleanup: :group_empty, outcome: :cancelled}
      else
        Boss.Agents.Process.run(executable, args, options)
      end
    end

    assert {:error, :publication_unknown} =
             Integration.publish(c.intent, Keyword.put(c.opts, :runner, runner))

    assert git!(c.source, ["rev-parse", "main"]) == c.sha
    assert File.read!(Path.join(c.intent["path"], "tracked.txt")) == "base"
  end

  test "persisted delivery authorization is checked immediately before publication", c do
    ready!(c)
    caller = self()

    authorize = fn ->
      send(caller, :authorization_checked)
      {:error, :stale_delivery}
    end

    assert {:error, :stale_delivery} =
             Integration.publish(c.intent, Keyword.put(c.opts, :authorize, authorize))

    assert_received :authorization_checked
    assert git!(c.source, ["rev-parse", "main"]) == c.base
    assert File.read!(Path.join(c.intent["path"], "tracked.txt")) == "base"
  end

  test "stop or unknown cleanup before publication never moves the target", c do
    ready!(c)
    cancelled = fn _, _, _ -> %{cleanup: :group_empty, outcome: :cancelled} end

    assert {:error, :cancelled} =
             Integration.publish(c.intent, Keyword.put(c.opts, :runner, cancelled))

    unknown = fn _, _, _ -> %{cleanup: :unknown, outcome: :failed} end

    assert {:error, :cleanup_unknown} =
             Integration.publish(c.intent, Keyword.put(c.opts, :runner, unknown))

    assert git!(c.source, ["rev-parse", "main"]) == c.base
  end

  @tag sha256: true
  test "SHA256 repositories publish the complete immutable candidate identity", c do
    ready!(c)
    assert byte_size(c.sha) == 64
    assert {:ok, c.sha} == Integration.publish(c.intent, c.opts)
    assert :ok = Integration.verify_published(c.intent, c.opts)
  end

  defp ready!(c) do
    git!(c.source, ["switch", "--detach"])
    assert :ok = Integration.prepare(c.intent, c.opts)
  end

  defp git!(path, args) do
    {out, code} =
      System.cmd("git", args,
        cd: path,
        stderr_to_stdout: true,
        env: [
          {"GIT_CONFIG_NOSYSTEM", "1"},
          {"GIT_CONFIG_GLOBAL", "/dev/null"},
          {"GIT_OPTIONAL_LOCKS", "0"}
        ]
      )

    assert code == 0, out
    String.trim_trailing(out, "\n")
  end
end
