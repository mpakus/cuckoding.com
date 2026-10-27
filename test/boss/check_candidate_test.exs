defmodule Boss.Checks.CandidateTest do
  use ExUnit.Case, async: false
  alias Boss.Agents.Workspace
  alias Boss.Checks.Candidate
  @moduletag skip: :os.type() != {:unix, :darwin}

  setup tags do
    root = Path.join(System.tmp_dir!(), "boss-check-candidate-#{Ecto.UUID.generate()}")
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
    File.write!(Path.join(source, "deleted.txt"), "delete me")
    File.write!(Path.join(source, ".gitignore"), "ignored.txt\n")
    git!(source, ["add", "."])
    git!(source, ["commit", "-m", "base"])

    project = %{
      id: 1,
      root_path: source,
      git_common_dir: Path.join(source, ".git"),
      base_branch: "main"
    }

    opts = [data_dir: data]
    {:ok, run} = Workspace.plan(project, Ecto.UUID.generate(), opts)
    {:ok, _} = Workspace.prepare(run, opts)
    %{root: root, source: source, run: run, opts: opts}
  end

  test "captures current files while preserving source and original HEAD, branch and index", c do
    File.write!(Path.join(c.run.path, "tracked.txt"), "staged")
    git!(c.run.path, ["add", "tracked.txt"])
    File.write!(Path.join(c.run.path, "tracked.txt"), "unstaged current")
    File.rm!(Path.join(c.run.path, "deleted.txt"))
    File.write!(Path.join(c.run.path, "new.txt"), "untracked")
    File.write!(Path.join(c.run.path, "ignored.txt"), "private ignored data")
    File.write!(Path.join(c.source, "tracked.txt"), "user edits")
    head = git!(c.run.path, ["rev-parse", "HEAD"])
    branch = git!(c.run.path, ["symbolic-ref", "HEAD"])
    index = git!(c.run.path, ["rev-parse", "--path-format=absolute", "--git-path", "index"])
    index_before = File.read!(index)
    {:ok, intent} = Candidate.plan(c.run, Ecto.UUID.generate(), c.opts)
    assert Enum.all?(Map.keys(intent), &is_binary/1)
    refute File.exists?(intent["path"])
    assert {:ok, %{candidate_commit: sha, path: path}} = Candidate.prepare(intent, c.opts)
    assert sha != head
    assert File.read!(Path.join(path, "tracked.txt")) == "unstaged current"
    assert File.read!(Path.join(path, "new.txt")) == "untracked"
    refute File.exists?(Path.join(path, "deleted.txt"))
    refute File.exists?(Path.join(path, "ignored.txt"))
    assert File.read!(index) == index_before
    assert git!(c.run.path, ["rev-parse", "HEAD"]) == head
    assert git!(c.run.path, ["symbolic-ref", "HEAD"]) == branch
    assert File.read!(Path.join(c.run.path, "tracked.txt")) == "unstaged current"
    assert File.read!(Path.join(c.source, "tracked.txt")) == "user edits"
    assert :ok = Candidate.verify(intent, sha, c.opts)
    assert {:error, :candidate_exists} = Candidate.prepare(intent, c.opts)
  end

  test "dirty files, untracked files, staged divergence and HEAD movement cannot verify", c do
    {:ok, intent} = Candidate.plan(c.run, Ecto.UUID.generate(), c.opts)
    {:ok, %{candidate_commit: sha, path: path}} = Candidate.prepare(intent, c.opts)
    File.write!(Path.join(path, "tracked.txt"), "changed")
    assert {:error, :candidate_changed} = Candidate.verify(intent, sha, c.opts)
    git!(path, ["add", "tracked.txt"])
    File.write!(Path.join(path, "tracked.txt"), "base")
    assert {:error, :candidate_changed} = Candidate.verify(intent, sha, c.opts)
    git!(path, ["reset", "--hard", sha])
    File.write!(Path.join(path, "new.txt"), "new")
    assert {:error, :candidate_changed} = Candidate.verify(intent, sha, c.opts)
    File.rm!(Path.join(path, "new.txt"))
    git!(path, ["commit", "--allow-empty", "-m", "different HEAD"])
    assert {:error, :candidate_changed} = Candidate.verify(intent, sha, c.opts)
  end

  test "fresh verification index detects edits hidden by index flags and filemode config", c do
    {:ok, intent} = Candidate.plan(c.run, Ecto.UUID.generate(), c.opts)
    {:ok, %{candidate_commit: sha, path: path}} = Candidate.prepare(intent, c.opts)
    git!(path, ["update-index", "--assume-unchanged", "tracked.txt"])
    File.write!(Path.join(path, "tracked.txt"), "hidden")
    assert git!(path, ["status", "--porcelain"]) == ""
    assert {:error, :candidate_changed} = Candidate.verify(intent, sha, c.opts)
    git!(path, ["update-index", "--no-assume-unchanged", "tracked.txt"])
    git!(path, ["reset", "--hard", sha])
    git!(path, ["update-index", "--skip-worktree", "tracked.txt"])
    File.write!(Path.join(path, "tracked.txt"), "hidden again")
    assert {:error, :candidate_changed} = Candidate.verify(intent, sha, c.opts)
    git!(path, ["update-index", "--no-skip-worktree", "tracked.txt"])
    git!(path, ["reset", "--hard", sha])
    git!(path, ["config", "core.filemode", "false"])
    File.chmod!(Path.join(path, "tracked.txt"), 0o755)
    assert {:error, :candidate_changed} = Candidate.verify(intent, sha, c.opts)
  end

  test "tampered paths, gitdir redirection and symlink parents are refused", c do
    {:ok, intent} = Candidate.plan(c.run, Ecto.UUID.generate(), c.opts)
    assert {:error, _} = Candidate.prepare(%{intent | "path" => c.source}, c.opts)
    {:ok, %{candidate_commit: sha, path: path}} = Candidate.prepare(intent, c.opts)
    gitfile = Path.join(path, ".git")
    File.rm!(gitfile)
    File.ln_s!(Path.join(c.run.path, ".git"), gitfile)
    assert {:error, :candidate_changed} = Candidate.verify(intent, sha, c.opts)
    File.rm!(gitfile)
    File.write!(gitfile, "gitdir: #{Path.join(c.source, ".git")}\n")
    assert {:error, :candidate_changed} = Candidate.verify(intent, sha, c.opts)
    {:ok, second} = Candidate.plan(c.run, Ecto.UUID.generate(), c.opts)
    File.ln_s!(c.source, second["path"])
    assert {:error, :candidate_exists} = Candidate.prepare(second, c.opts)
  end

  test "unsafe checkout configuration and gitlinks fail without changing the original index", c do
    {:ok, intent} = Candidate.plan(c.run, Ecto.UUID.generate(), c.opts)
    git!(c.source, ["config", "filter.unsafe.clean", "touch should-not-exist"])
    assert {:error, :unsupported_git_filter} = Candidate.prepare(intent, c.opts)
    git!(c.source, ["config", "--remove-section", "filter.unsafe"])
    git!(c.source, ["config", "core.sparseCheckout", "true"])
    assert {:error, :unsupported_sparse_checkout} = Candidate.prepare(intent, c.opts)
    git!(c.source, ["config", "core.sparseCheckout", "false"])

    git!(c.run.path, [
      "update-index",
      "--add",
      "--cacheinfo",
      "160000,#{c.run.base_commit},submodule"
    ])

    git!(c.run.path, ["commit", "-m", "gitlink"])
    # A materialized gitlink is preserved by add -A and must not be silently accepted.
    File.mkdir!(Path.join(c.run.path, "submodule"))
    assert {:error, :unsupported_submodule} = Candidate.prepare(intent, c.opts)
    refute File.exists?(intent["path"])
  end

  test "native unknown cleanup is distinct and never leads to a check workspace", c do
    {:ok, intent} = Candidate.plan(c.run, Ecto.UUID.generate(), c.opts)
    unknown = fn _, _, _ -> %{cleanup: :unknown, outcome: :failed} end

    assert {:error, :cleanup_unknown} =
             Candidate.prepare(intent, Keyword.put(c.opts, :runner, unknown))

    refute File.exists?(intent["path"])
  end

  test "generic tree verification allows an attached exact HEAD but rejects hidden edits", c do
    assert :ok = Candidate.verify_tree(c.run.path, c.run.base_commit, c.opts)
    git!(c.run.path, ["update-index", "--assume-unchanged", "tracked.txt"])
    File.write!(Path.join(c.run.path, "tracked.txt"), "hidden planner mutation")

    assert {:error, :candidate_changed} =
             Candidate.verify_tree(c.run.path, c.run.base_commit, c.opts)

    assert {:error, :candidate_changed} = Candidate.verify_tree(".", c.run.base_commit, c.opts)
  end

  test "changing source between private captures refuses the snapshot", c do
    {:ok, intent} = Candidate.plan(c.run, Ecto.UUID.generate(), c.opts)

    runner = fn executable, args, options ->
      result = Boss.Agents.Process.run(executable, args, options)

      if "write-tree" in args and is_nil(Process.get(:changed_candidate_source)) do
        File.write!(Path.join(c.run.path, "tracked.txt"), "concurrent edit")
        Process.put(:changed_candidate_source, true)
      end

      result
    end

    assert {:error, :source_changed} =
             Candidate.prepare(intent, Keyword.put(c.opts, :runner, runner))

    refute File.exists?(intent["path"])
    assert File.read!(Path.join(c.run.path, "tracked.txt")) == "concurrent edit"
  end

  @tag sha256: true
  test "SHA256 repositories retain the full candidate commit and CAS ref identity", c do
    {:ok, intent} = Candidate.plan(c.run, Ecto.UUID.generate(), c.opts)
    assert {:ok, %{candidate_commit: sha}} = Candidate.prepare(intent, c.opts)
    assert byte_size(sha) == 64
    assert git!(c.source, ["rev-parse", intent["ref"]]) == sha
    assert :ok = Candidate.verify(intent, sha, c.opts)
  end

  for kind <- [:directory, :file, :symlink] do
    @tag parent_kind: kind
    test "late candidate parent #{kind} is revalidated without changing its owner", c do
      {:ok, intent} = Candidate.plan(c.run, Ecto.UUID.generate(), c.opts)
      shared = Path.dirname(intent["path"])
      source_mode = File.stat!(c.source).mode

      runner = fn executable, args, opts ->
        result = Boss.Agents.Process.run(executable, args, opts)

        if "show-ref" in args and result.exit_code == 1 do
          case c.parent_kind do
            :directory ->
              File.mkdir!(shared)
              File.chmod!(shared, 0o751)

            :file ->
              File.write!(shared, "preserve file")

            :symlink ->
              File.ln_s!(c.source, shared)
          end
        end

        result
      end

      result = Candidate.prepare(intent, Keyword.put(c.opts, :runner, runner))

      case c.parent_kind do
        :directory ->
          assert {:ok, _} = result
          assert Bitwise.band(File.stat!(shared).mode, 0o777) == 0o751

        :file ->
          assert {:error, :candidate_path} = result
          assert File.read!(shared) == "preserve file"

        :symlink ->
          assert {:error, :candidate_path} = result
          assert File.lstat!(shared).type == :symlink
          refute File.exists?(Path.join(c.source, intent["check_id"]))
          assert File.stat!(c.source).mode == source_mode
      end
    end
  end

  for format <- [:sha1, :sha256] do
    @tag sha256: format == :sha256
    test "retains a two-parent #{format} merge without changing either original checkout", c do
      {approved, original} = approved_candidate(c)
      File.write!(Path.join(c.source, "target.txt"), "parallel result")
      git!(c.source, ["add", "target.txt"])
      git!(c.source, ["commit", "-m", "advance target"])
      target = git!(c.source, ["rev-parse", "HEAD"])
      File.write!(Path.join(c.source, "tracked.txt"), "staged user edit")
      git!(c.source, ["add", "tracked.txt"])
      File.write!(Path.join(c.source, "tracked.txt"), "unstaged user edit")
      index = Path.join(c.source, ".git/index")
      index_before = File.read!(index)
      status = git!(c.source, ["status", "--porcelain"])
      {:ok, merged} = Candidate.plan(c.run, Ecto.UUID.generate(), c.opts)

      assert {:ok, %{candidate_commit: sha}} =
               Candidate.prepare_merge(merged, target, original, c.opts)

      assert byte_size(sha) == byte_size(target)

      assert git!(c.source, ["rev-list", "--parents", "-n", "1", sha]) ==
               "#{sha} #{target} #{original}"

      assert File.read!(Path.join(merged["path"], "agent.txt")) == "approved result"
      assert File.read!(Path.join(merged["path"], "target.txt")) == "parallel result"
      assert File.read!(Path.join(merged["path"], "tracked.txt")) == "base"
      assert :ok = Candidate.verify_merge(merged, sha, target, original, c.opts)

      assert {:error, :candidate_changed} =
               Candidate.verify_merge(merged, sha, original, target, c.opts)

      assert :ok = Candidate.verify(approved, original, c.opts)
      assert File.read!(index) == index_before
      assert git!(c.source, ["status", "--porcelain"]) == status
      assert git!(c.source, ["rev-parse", "HEAD"]) == target
      assert git!(c.source, ["symbolic-ref", "HEAD"]) == "refs/heads/main"
      assert git!(c.run.path, ["rev-parse", "HEAD"]) == c.run.base_commit

      assert {:error, :candidate_exists} =
               Candidate.prepare_merge(merged, target, original, c.opts)
    end
  end

  test "conflict output never becomes a retained merge candidate", c do
    File.write!(Path.join(c.run.path, "tracked.txt"), "agent change")
    {_approved, original} = approved_candidate(c)
    File.write!(Path.join(c.source, "tracked.txt"), "target change")
    git!(c.source, ["add", "tracked.txt"])
    git!(c.source, ["commit", "-m", "conflicting target"])
    target = git!(c.source, ["rev-parse", "HEAD"])
    {:ok, merged} = Candidate.plan(c.run, Ecto.UUID.generate(), c.opts)
    assert {:error, :merge_conflict} = Candidate.prepare_merge(merged, target, original, c.opts)
    refute File.exists?(merged["path"])
    assert git!(c.source, ["for-each-ref", "--format=%(objectname)", merged["ref"]]) == ""
    assert git!(c.source, ["rev-parse", "HEAD"]) == target
    refute File.exists?(Path.join(c.source, ".git/MERGE_HEAD"))
  end

  test "a configured merge driver is rejected before any merge effect", c do
    File.write!(Path.join(c.run.path, ".gitattributes"), "tracked.txt merge=unsafe\n")
    File.write!(Path.join(c.run.path, "tracked.txt"), "agent change")
    {_approved, original} = approved_candidate(c)
    File.write!(Path.join(c.source, "tracked.txt"), "target change")
    git!(c.source, ["add", "tracked.txt"])
    git!(c.source, ["commit", "-m", "advance"])
    target = git!(c.source, ["rev-parse", "HEAD"])
    {:ok, merged} = Candidate.plan(c.run, Ecto.UUID.generate(), c.opts)
    marker = Path.join(c.root, "driver-ran")
    git!(c.source, ["config", "merge.unsafe.driver", "touch '#{marker}'"])

    assert {:error, :unsupported_git_merge_driver} =
             Candidate.prepare_merge(merged, target, original, c.opts)

    refute File.exists?(marker)
    refute File.exists?(merged["path"])
  end

  test "merge rejects aliases, duplicate parents and unknown cleanup without retry", c do
    {_approved, original} = approved_candidate(c)
    {:ok, merged} = Candidate.plan(c.run, Ecto.UUID.generate(), c.opts)

    assert {:error, :invalid_candidate} =
             Candidate.prepare_merge(merged, "main", original, c.opts)

    assert {:error, :invalid_candidate} =
             Candidate.prepare_merge(merged, original, original, c.opts)

    runner = fn executable, args, opts ->
      if "merge-tree" in args,
        do: %{cleanup: :unknown, outcome: :failed},
        else: Boss.Agents.Process.run(executable, args, opts)
    end

    assert {:error, :cleanup_unknown} =
             Candidate.prepare_merge(
               merged,
               c.run.base_commit,
               original,
               Keyword.put(c.opts, :runner, runner)
             )

    refute File.exists?(merged["path"])
    assert git!(c.source, ["for-each-ref", "--format=%(objectname)", merged["ref"]]) == ""
  end

  defp approved_candidate(c) do
    File.write!(Path.join(c.run.path, "agent.txt"), "approved result")
    {:ok, intent} = Candidate.plan(c.run, Ecto.UUID.generate(), c.opts)
    {:ok, %{candidate_commit: sha}} = Candidate.prepare(intent, c.opts)
    {intent, sha}
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
