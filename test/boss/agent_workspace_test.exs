defmodule Boss.Agents.WorkspaceTest do
  use ExUnit.Case, async: false
  alias Boss.Agents.Workspace

  setup do
    root =
      Path.join(
        System.tmp_dir!(),
        "boss-workspace-#{Base.url_encode64(:crypto.strong_rand_bytes(12), padding: false)}"
      )

    File.mkdir!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    lexical_root = root
    {physical, 0} = System.cmd("/bin/pwd", ["-P"], cd: root)
    root = String.trim(physical)
    repo = Path.join(root, "source with spaces")
    data = Path.join(root, "data")
    File.mkdir!(repo)
    File.mkdir!(data)
    git!(repo, ["init", "-b", "main"])
    git!(repo, ["config", "user.name", "BOSS test"])
    git!(repo, ["config", "user.email", "test@example.invalid"])
    git!(repo, ["config", "commit.gpgSign", "false"])
    base = commit(repo, "source.txt", "base")

    project = %{
      id: 1,
      root_path: repo,
      git_common_dir: Path.join(repo, ".git"),
      base_branch: "main"
    }

    %{
      root: root,
      repo: repo,
      data: data,
      lexical_data: Path.join(lexical_root, "data"),
      base: base,
      project: project,
      opts: [data_dir: data, runner: &fixture_runner/3]
    }
  end

  test "planning is read-only and preparation pins the base while preserving a dirty checkout",
       c do
    assert {:ok, intent} = Workspace.plan(c.project, "run-one", c.opts)
    refute File.exists?(intent.path)
    assert intent.base_commit == c.base
    commit(c.repo, "later.txt", "new base tip")
    File.write!(Path.join(c.repo, "source.txt"), "user edit")
    File.write!(Path.join(c.repo, "notes.txt"), "user notes")
    before = git!(c.repo, ["status", "--porcelain=v1"])
    assert {:ok, workspace} = Workspace.prepare(intent, c.opts)
    assert workspace.head_commit == c.base
    assert workspace.path == intent.path
    assert File.read!(Path.join(workspace.path, "source.txt")) == "base"
    refute File.exists?(Path.join(workspace.path, "later.txt"))
    assert git!(c.repo, ["status", "--porcelain=v1"]) == before
    assert File.read!(Path.join(c.repo, "source.txt")) == "user edit"
  end

  test "inspect and repeated preparation preserve commits and dirty output", c do
    {:ok, intent} = Workspace.plan(c.project, "repeat", c.opts)
    {:ok, _} = Workspace.prepare(intent, c.opts)
    head = commit(intent.path, "result.txt", "agent work")
    File.write!(Path.join(intent.path, "untracked.txt"), "keep")
    encoded = Map.new(intent, fn {key, value} -> {Atom.to_string(key), value} end)
    assert {:ok, %{head_commit: ^head}} = Workspace.inspect(encoded, c.opts)
    assert {:ok, %{head_commit: ^head}} = Workspace.prepare(encoded, c.opts)
    assert File.read!(Path.join(intent.path, "untracked.txt")) == "keep"
  end

  test "missing output with an existing branch is not reconstructed", c do
    {:ok, intent} = Workspace.plan(c.project, "missing", c.opts)
    {:ok, _} = Workspace.prepare(intent, c.opts)
    git!(c.repo, ["worktree", "remove", intent.path])
    assert {:error, :workspace_missing} = Workspace.inspect(intent, c.opts)
    assert {:error, :workspace_conflict} = Workspace.prepare(intent, c.opts)
    refute File.exists?(intent.path)
  end

  test "tampered paths and identities are rejected without changes", c do
    {:ok, intent} = Workspace.plan(c.project, "identity", c.opts)

    for changed <- [
          %{intent | path: c.repo},
          %{intent | branch: "main"},
          %{intent | git_common_dir: c.data},
          %{intent | base_commit: "main"}
        ] do
      assert {:error, _} = Workspace.prepare(changed, c.opts)
    end

    refute File.exists?(intent.path)
    assert git!(c.repo, ["symbolic-ref", "--short", "HEAD"]) == "main"
  end

  test "hooks are disabled and executable filters are refused before checkout", c do
    marker = Path.join(c.root, "hook-ran")
    hook = Path.join(c.repo, ".git/hooks/post-checkout")
    File.write!(hook, "#!/bin/sh\ntouch '#{marker}'\n")
    File.chmod!(hook, 0o700)
    {:ok, intent} = Workspace.plan(c.project, "hooks", c.opts)
    assert {:ok, _} = Workspace.prepare(intent, c.opts)
    refute File.exists?(marker)
    git!(c.repo, ["config", "filter.evil.smudge", "touch #{marker}"])
    assert {:error, :unsupported_git_filter} = Workspace.plan(c.project, "filter", c.opts)
    refute File.exists?(marker)
  end

  test "cleanup uncertainty remains distinguishable even for read-only Git", c do
    runner = fn _, _, _ -> %{outcome: :failed, cleanup: :unknown} end

    assert {:error, :cleanup_unknown} =
             Workspace.plan(c.project, "unknown", Keyword.put(c.opts, :runner, runner))
  end

  test "symlink parents and data inside the source checkout are rejected", c do
    File.ln_s!(c.repo, Path.join(c.data, "projects"))
    assert {:error, :invalid_workspace_path} = Workspace.plan(c.project, "linked", c.opts)

    assert {:error, :invalid_workspace_path} =
             Workspace.plan(c.project, "nested", Keyword.put(c.opts, :data_dir, c.repo))

    refute File.exists?(Path.join(c.repo, "1"))
  end

  test "a nonmatching worktree is preserved and rejected", c do
    {:ok, intent} = Workspace.plan(c.project, "foreign", c.opts)
    File.mkdir_p!(Path.dirname(intent.path))
    git!(c.repo, ["worktree", "add", "-b", "some-other-branch", intent.path])
    File.write!(Path.join(intent.path, "keep.txt"), "foreign contents")
    assert {:error, :workspace_mismatch} = Workspace.prepare(intent, c.opts)
    assert File.read!(Path.join(intent.path, "keep.txt")) == "foreign contents"
    assert git!(intent.path, ["symbolic-ref", "--short", "HEAD"]) == "some-other-branch"
  end

  test "unknown cleanup after worktree creation keeps the effect and its uncertainty", c do
    {:ok, intent} = Workspace.plan(c.project, "unknown-add", c.opts)

    runner = fn executable, args, opts ->
      result = fixture_runner(executable, args, opts)
      if "add" in args, do: %{result | cleanup: :unknown}, else: result
    end

    assert {:error, :cleanup_unknown} =
             Workspace.prepare(intent, Keyword.put(c.opts, :runner, runner))

    assert File.read!(Path.join(intent.path, "source.txt")) == "base"
    assert git!(intent.path, ["symbolic-ref", "--short", "HEAD"]) == intent.branch
  end

  test "inherited Git directory cannot redirect repository commands", c do
    previous = System.get_env("GIT_DIR")
    System.put_env("GIT_DIR", Path.join(c.root, "nonexistent"))

    try do
      assert {:ok, %{base_commit: base}} = Workspace.plan(c.project, "environment", c.opts)
      assert base == c.base
    after
      if previous, do: System.put_env("GIT_DIR", previous), else: System.delete_env("GIT_DIR")
    end
  end

  test "commit replacement cannot substitute files behind the pinned SHA", c do
    original = c.base
    replacement = commit(c.repo, "source.txt", "replacement")
    git!(c.repo, ["replace", original, replacement])
    git!(c.repo, ["update-ref", "refs/heads/pinned", original])
    project = %{c.project | base_branch: "pinned"}
    {:ok, intent} = Workspace.plan(project, "replacement", c.opts)
    assert intent.base_commit == original
    assert {:ok, _} = Workspace.prepare(intent, c.opts)
    assert File.read!(Path.join(intent.path, "source.txt")) == "base"
  end

  test "trusted data-root aliases resolve physically before descendant validation", c do
    assert {:ok, temp_intent} =
             Workspace.plan(
               c.project,
               "system-temp",
               Keyword.put(c.opts, :data_dir, c.lexical_data)
             )

    assert String.starts_with?(temp_intent.path, c.data <> "/")
    alias_path = Path.join(c.root, "data-alias")
    File.ln_s!(c.data, alias_path)
    opts = Keyword.put(c.opts, :data_dir, alias_path)
    assert {:ok, intent} = Workspace.plan(c.project, "root-alias", opts)
    assert String.starts_with?(intent.path, c.data <> "/")
    refute String.starts_with?(intent.path, alias_path <> "/")
    assert {:ok, _} = Workspace.prepare(intent, opts)
    File.ln_s!(c.repo, Path.join(c.data, "redirected"))

    assert {:error, :invalid_workspace_path} =
             Workspace.plan(
               c.project,
               "outside",
               Keyword.put(c.opts, :data_dir, Path.join(c.data, "redirected"))
             )

    cycle = Path.join(c.root, "cycle")
    File.ln_s!(cycle, cycle)

    assert {:error, :invalid_workspace_path} =
             Workspace.plan(c.project, "cycle", Keyword.put(c.opts, :data_dir, cycle))
  end

  @tag native: true
  @tag skip: :os.type() != {:unix, :darwin}
  test "production native transport prepares and verifies a real worktree", c do
    opts = Keyword.delete(c.opts, :runner)
    assert {:ok, intent} = Workspace.plan(c.project, "native", opts)
    assert {:ok, %{head_commit: head}} = Workspace.prepare(intent, opts)
    assert head == c.base
    assert {:ok, %{head_commit: ^head}} = Workspace.inspect(intent, opts)
    assert File.read!(Path.join(intent.path, "source.txt")) == "base"
  end

  test "branch-conditional configuration cannot activate an unseen checkout filter", c do
    marker = Path.join(c.root, "conditional-filter-ran")
    config = Path.join(c.root, "conditional.gitconfig")
    File.write!(config, "[filter \"review\"]\n  smudge = touch '#{marker}'\n")
    commit(c.repo, ".gitattributes", "source.txt filter=review\n")
    {:ok, intent} = Workspace.plan(c.project, "before-conditional", c.opts)
    git!(c.repo, ["config", "includeIf.onbranch:codex/**.path", config])
    assert {:error, :unsupported_git_config} = Workspace.plan(c.project, "conditional", c.opts)
    assert {:error, :unsupported_git_config} = Workspace.prepare(intent, c.opts)
    refute File.exists?(marker)
  end

  test "Stop cause survives Git failure while unknown cleanup takes precedence", c do
    cancelled = fn _, _, _ -> %{outcome: :cancelled, cleanup: :group_empty} end

    assert {:error, :cancelled} =
             Workspace.plan(c.project, "stopped", Keyword.put(c.opts, :runner, cancelled))

    unknown = fn _, _, _ -> %{outcome: :cancelled, cleanup: :unknown} end

    assert {:error, :cleanup_unknown} =
             Workspace.plan(c.project, "unknown-stop", Keyword.put(c.opts, :runner, unknown))
  end

  test "concurrent run and candidate worktrees share fresh parents without losing ownership", c do
    parent = self()

    barrier = fn executable, args, opts ->
      result = fixture_runner(executable, args, opts)

      if "show-ref" in args and result.exit_code == 1 do
        send(parent, {:parents_ready, self()})

        receive do
          :create_parents -> :ok
        after
          5_000 -> flunk("parent creation barrier expired")
        end
      end

      result
    end

    for round <- 1..2 do
      opts = Keyword.put(c.opts, :data_dir, Path.join(c.data, "round#{round}"))

      intents =
        for n <- 1..8 do
          {:ok, intent} = Workspace.plan(c.project, "parallel-#{round}-#{n}", opts)
          intent
        end

      results =
        parallel_parents(intents, &Workspace.prepare(&1, Keyword.put(opts, :runner, barrier)))

      assert Enum.all?(results, &match?({:ok, _}, &1)), inspect(results)
      assert length(Enum.uniq_by(intents, & &1.path)) == 8

      candidates =
        for intent <- intents do
          {:ok, candidate} = Boss.Checks.Candidate.plan(intent, Ecto.UUID.generate(), opts)
          candidate
        end

      results =
        parallel_parents(
          candidates,
          &Boss.Checks.Candidate.prepare(&1, Keyword.put(opts, :runner, barrier))
        )

      assert Enum.all?(results, &match?({:ok, _}, &1)), inspect(results)

      for {intent, {:ok, candidate}} <- Enum.zip(candidates, results) do
        assert :ok = Boss.Checks.Candidate.verify(intent, candidate.candidate_commit, opts)
        assert File.read!(Path.join(candidate.path, "source.txt")) == "base"
      end
    end

    assert git!(c.repo, ["status", "--porcelain"]) == ""
  end

  test "late shared parents preserve existing modes and reject files or symlinks", c do
    for kind <- [:directory, :file, :symlink] do
      opts = Keyword.put(c.opts, :data_dir, Path.join(c.data, to_string(kind)))
      {:ok, intent} = Workspace.plan(c.project, "late-#{kind}", opts)
      shared = Path.join(opts[:data_dir], "projects")

      runner = fn executable, args, options ->
        result = fixture_runner(executable, args, options)

        if "show-ref" in args and result.exit_code == 1 do
          File.mkdir!(opts[:data_dir])

          case kind do
            :directory ->
              File.mkdir!(shared)
              File.chmod!(shared, 0o751)

            :file ->
              File.write!(shared, "preserve file")

            :symlink ->
              File.ln_s!(c.repo, shared)
          end
        end

        result
      end

      case kind do
        :directory ->
          assert {:ok, _} = Workspace.prepare(intent, Keyword.put(opts, :runner, runner))
          assert Bitwise.band(File.stat!(shared).mode, 0o777) == 0o751

        :file ->
          assert {:error, :workspace_unwritable} =
                   Workspace.prepare(intent, Keyword.put(opts, :runner, runner))

          assert File.read!(shared) == "preserve file"

        :symlink ->
          assert {:error, :workspace_unwritable} =
                   Workspace.prepare(intent, Keyword.put(opts, :runner, runner))

          assert File.lstat!(shared).type == :symlink
          refute File.exists?(Path.join(c.repo, "1"))
      end
    end
  end

  defp parallel_parents(intents, fun) do
    jobs = Enum.map(intents, &Task.async(fn -> fun.(&1) end))

    pids =
      for _ <- intents do
        assert_receive {:parents_ready, pid}, 5_000
        pid
      end

    Enum.each(pids, &send(&1, :create_parents))
    Enum.map(jobs, &Task.await(&1, 20_000))
  end

  defp fixture_runner(executable, args, opts) do
    {output, code} =
      System.cmd(executable, args, cd: opts[:cd], env: opts[:env], stderr_to_stdout: true)

    opts[:on_event].({:stdout, output})

    %{
      outcome: :exited,
      exit_kind: :exit,
      exit_code: code,
      signal: nil,
      eof: %{stdout: true, stderr: true},
      cleanup: :group_empty
    }
  end

  defp git!(repo, args) do
    {output, 0} = System.cmd("git", ["-C", repo | args], stderr_to_stdout: true)
    String.trim_trailing(output, "\n")
  end

  defp commit(repo, file, contents) do
    File.write!(Path.join(repo, file), contents)
    git!(repo, ["add", file])
    git!(repo, ["-c", "core.hooksPath=/dev/null", "commit", "-m", "fixture"])
    git!(repo, ["rev-parse", "HEAD"])
  end
end
