defmodule Boss.BackendRecoveryTest do
  use ExUnit.Case, async: false
  @moduletag skip: :os.type() != {:unix, :darwin}
  @moduletag timeout: 120_000

  setup do
    root = Path.join(System.tmp_dir!(), "boss-backend-recovery-#{Ecto.UUID.generate()}")
    File.mkdir!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    {physical, 0} = System.cmd("/bin/pwd", ["-P"], cd: root)
    root = String.trim(physical)
    source = Path.join(root, "source")
    File.mkdir!(source)
    File.mkdir!(Path.join(root, "bin"))
    File.mkdir!(Path.join(root, "tmp"))
    fixture = Path.expand("../fixtures/backend_recovery_cli.py", __DIR__)
    File.cp!(fixture, Path.join(root, "bin/codex"))
    File.chmod!(Path.join(root, "bin/codex"), 0o700)
    File.cp!(fixture, Path.join(source, "check.py"))
    File.write!(Path.join(source, "result.txt"), "base")

    for args <- [
          ["init", "-b", "main"],
          ["config", "user.name", "Fixture"],
          ["config", "user.email", "fixture@example.invalid"],
          ["add", "."],
          ["commit", "-m", "base"],
          ["switch", "-c", "user-work"]
        ],
        do: git(source, args)

    File.write!(Path.join(source, "user.txt"), "preserve local edits")
    %{root: root, source: source, base: git(source, ["rev-parse", "main"])}
  end

  for boundary <- ~w(plan implement check review post_check) do
    test "whole backend death during #{boundary} preserves evidence and never respawns", c do
      boundary = unquote(boundary)
      vm = boot(c.root, boundary, "start")
      before = wait_json(c.root, "before", vm)
      assert before["elixir"] == System.version()
      assert before["otp"] == System.otp_release()
      {:os_pid, vm_pid} = Port.info(vm, :os_pid)
      assert before["vm_pid"] == to_string(vm_pid)
      owned = read_json(c.root, "processes")
      pids = Map.take(owned, ~w(leader child guardian))
      identities = Map.new(pids, fn {_, pid} -> {pid, identity(pid)} end)
      assert Enum.all?(identities, fn {_, value} -> value != nil end)
      on_exit(fn -> cleanup_owned(identities) end)
      [delivery] = before["deliveries"]
      running = Enum.find(before["steps"], &(&1["kind"] == boundary))
      assert running["status"] == "running"
      assert running["receipt"] == %{}
      finished = Enum.filter(before["steps"], &(&1["status"] == "finished"))
      assert before["batch"]["status"] == "running"
      result = if boundary == "plan", do: "base", else: "candidate-1\n"
      assert File.read!(Path.join(owned["cwd"], "result.txt")) == result
      calls = calls(c.root, "calls")
      check_calls = calls(c.root, "check-calls")
      target = git(c.source, ["rev-parse", "main"])

      {expected_calls, expected_checks} =
        case boundary do
          "plan" -> {~w(plan), 0}
          "implement" -> {~w(plan implement), 0}
          "check" -> {~w(plan implement), 1}
          "review" -> {~w(plan implement review), 1}
          "post_check" -> {~w(plan implement review), 2}
        end

      assert calls == expected_calls
      assert length(check_calls) == expected_checks

      if boundary in ~w(plan review) do
        # A complete report and terminal JSONL event still lack exit/EOF/cleanup evidence.
        assert owned["terminal_emitted"]
        assert String.starts_with?(owned["report_path"], Path.join(c.root, "tmp") <> "/")
        report = owned["report_path"] |> File.read!() |> JSON.decode!()
        assert report["summary"] != ""
        if boundary == "review", do: assert(report["verdict"] == "approved")
      end

      if boundary == "post_check" do
        assert target != c.base
        assert target == delivery["integration_intent"]["candidate_commit"]

        assert Enum.find(finished, &(&1["kind"] == "publish"))["receipt"]["candidate_commit"] ==
                 target
      else
        assert target == c.base
        assert delivery["integration_intent"] == %{}
      end

      kill_vm(vm)
      assert_receive {^vm, {:exit_status, status}}, 5_000
      refute status == 0
      eventually(fn -> Enum.all?(pids, fn {_, pid} -> not alive?(pid) end) end, 250)

      replacement = boot(c.root, boundary, "recover")
      recovered = wait_json(c.root, "recovered", replacement)
      assert recovered["vm_pid"] != before["vm_pid"]
      assert recovered["active"] == 0
      assert recovered["batch"]["status"] == "paused"
      assert recovered["batch"]["task_ids"] == before["batch"]["task_ids"]
      assert recovered["batch"]["command_id"] == before["batch"]["command_id"]
      assert Enum.map(recovered["requests"], & &1["status"]) |> Enum.sort() == ~w(paused started)
      [interrupted] = recovered["deliveries"]
      assert interrupted["status"] == "interrupted" and interrupted["cleanup"] == "unknown"

      for key <-
            ~w(id task_id spec_revision_id command_id reviewer check_config config_hash intent integration_intent integration_command_id),
          do: assert(interrupted[key] == delivery[key])

      assert Enum.find(recovered["steps"], &(&1["id"] == running["id"])) ==
               Map.merge(running, %{
                 "status" => "interrupted",
                 "receipt" => %{"status" => "interrupted", "cleanup" => "unknown"}
               })

      assert Enum.all?(finished, &(&1 in recovered["steps"]))
      assert Enum.all?(before["events"], &(&1 in recovered["events"]))

      assert Enum.find(recovered["tasks"], &(&1["id"] == delivery["task_id"]))["state"] ==
               "interrupted"

      final = wait_json(c.root, "after_resume", replacement)
      assert_receive {^replacement, {:exit_status, 0}}, 5_000
      assert final["batch"]["status"] == "blocked"
      assert final["deliveries"] == recovered["deliveries"]
      assert final["steps"] == recovered["steps"]
      assert final["active"] == 0
      assert calls(c.root, "calls") == calls
      assert calls(c.root, "check-calls") == check_calls
      assert git(c.source, ["rev-parse", "main"]) == target
      assert git(c.source, ["rev-parse", "HEAD"]) == c.base
      assert git(c.source, ["branch", "--show-current"]) == "user-work"
      assert git(c.source, ["status", "--porcelain"]) == "?? user.txt"
      assert File.read!(Path.join(c.source, "user.txt")) == "preserve local edits"
      assert File.read!(Path.join(owned["cwd"], "result.txt")) == result

      if boundary in ~w(check review post_check) do
        snapshot = Enum.find(finished, &(&1["kind"] == "snapshot"))
        candidate = snapshot["receipt"]["workspace"]
        sha = snapshot["receipt"]["candidate_commit"]
        assert git(candidate["path"], ["rev-parse", "HEAD"]) == sha
        assert git(c.source, ["rev-parse", candidate["ref"]]) == sha
        assert git(candidate["path"], ["status", "--porcelain"]) == ""

        if boundary in ~w(check review),
          do: assert(running["input"]["candidate_commit"] == sha)
      end

      refute Enum.any?(final["tasks"], &(&1["state"] in ~w(ready_to_merge done)))
    end
  end

  for drift <- ~w(unchanged dirty ref advanced rewritten) do
    @tag drift: drift
    test "Ready restart with #{drift} Git state preserves evidence before explicit Resume", c do
      drift = unquote(drift)
      boundary = if drift == "unchanged", do: "ready", else: "ready_" <> drift
      vm = boot(c.root, boundary, "start")
      before = wait_json(c.root, "before", vm)
      {:os_pid, pid} = Port.info(vm, :os_pid)
      assert before["vm_pid"] == to_string(pid)
      assert before["active"] == 0
      assert before["batch"]["status"] == "paused"
      [delivery] = before["deliveries"]
      assert delivery["status"] == "ready_to_merge"
      assert delivery["cleanup"] == "group_empty"
      assert delivery["integration_command_id"] == nil
      assert delivery["integration_intent"] == %{}
      assert Enum.all?(before["steps"], &(&1["status"] == "finished"))
      review = Enum.find(before["steps"], &(&1["kind"] == "review"))
      check = Enum.find(before["steps"], &(&1["id"] == review["input"]["check_step_id"]))
      assert review["receipt"]["report"]["verdict"] == "approved"
      assert review["receipt"]["report"]["issues"] == []
      sha = review["input"]["candidate_commit"]
      candidate = check["input"]["workspace"]
      assert sha == check["input"]["candidate_commit"]
      assert Path.wildcard(Path.join(c.root, "tmp/boss-review-*")) == []
      assert calls(c.root, "calls") == ~w(plan implement review)
      [first_check] = calls(c.root, "check-calls")
      assert first_check == candidate["path"]
      assert git(c.source, ["rev-parse", "main"]) == c.base

      kill_vm(vm)
      assert_receive {^vm, {:exit_status, status}}, 5_000
      refute status == 0
      offline_target = change_offline(c, drift, candidate, sha)
      replacement = boot(c.root, boundary, "recover")
      recovered = wait_json(c.root, "recovered", replacement)
      paused = wait_json(c.root, "paused_replay", replacement)
      refute recovered["vm_pid"] == before["vm_pid"]

      for saved <- [recovered, paused] do
        assert saved["active"] == 0

        for key <- ~w(batch deliveries tasks requests items steps events),
            do: assert(saved[key] == before[key])
      end

      assert git(c.source, ["rev-parse", "main"]) == offline_target
      assert calls(c.root, "calls") == ~w(plan implement review)
      assert calls(c.root, "check-calls") == [first_check]
      File.write!(Path.join(c.root, "resume"), "")
      final = wait_json(c.root, "after_resume", replacement)
      assert_receive {^replacement, {:exit_status, 0}}, 5_000
      assert final["active"] == 0
      [finished] = final["deliveries"]
      [item] = before["items"]
      assert finished["cleanup"] == "group_empty"
      assert finished["integration_command_id"] == item["integration_command_id"]
      assert final["items"] == before["items"]
      assert final["requests"] == before["requests"]
      assert Enum.all?(before["steps"], &(&1 in final["steps"]))
      assert Enum.all?(before["events"], &(&1 in final["events"]))

      if drift in ~w(dirty ref rewritten) do
        assert final["batch"]["status"] == "blocked"
        assert finished["status"] == "blocked"
        assert Enum.map(final["tasks"], & &1["state"]) == ["blocked"]
        assert finished["integration_intent"] == %{}
        assert length(final["steps"]) == length(before["steps"])
        assert final["steps"] == before["steps"]
        assert calls(c.root, "calls") == ~w(plan implement review)
        assert calls(c.root, "check-calls") == [first_check]
        assert git(c.source, ["rev-parse", "main"]) == offline_target

        if drift == "rewritten",
          do: assert(finished["reason"] =~ "no longer descends from the original base"),
          else: assert(finished["reason"] =~ "could not verify the saved candidate")
      else
        assert_published(c, drift, final, check, review, offline_target)
      end

      assert git(candidate["path"], ["rev-parse", "HEAD"]) == sha
      expected_ref = if drift == "ref", do: c.base, else: sha
      assert git(c.source, ["rev-parse", candidate["ref"]]) == expected_ref
      expected_file = if drift == "dirty", do: "offline tamper\n", else: "candidate-1\n"
      assert File.read!(Path.join(candidate["path"], "result.txt")) == expected_file

      if drift == "dirty",
        do: assert(git(candidate["path"], ["ls-files", "-v", "result.txt"]) == "h result.txt")

      assert Path.wildcard(Path.join(c.root, "tmp/boss-review-*")) == []
      assert git(c.source, ["rev-parse", "HEAD"]) == c.base
      assert git(c.source, ["branch", "--show-current"]) == "user-work"
      assert git(c.source, ["status", "--porcelain"]) == "?? user.txt"
      assert File.read!(Path.join(c.source, "user.txt")) == "preserve local edits"
    end
  end

  defp change_offline(c, "unchanged", _, _), do: c.base

  defp change_offline(c, "dirty", candidate, _) do
    git(candidate["path"], ["update-index", "--assume-unchanged", "result.txt"])
    File.write!(Path.join(candidate["path"], "result.txt"), "offline tamper\n")
    assert git(candidate["path"], ["status", "--porcelain"]) == ""
    c.base
  end

  defp change_offline(c, "ref", candidate, sha) do
    git(c.source, ["update-ref", candidate["ref"], c.base, sha])
    c.base
  end

  defp change_offline(c, "advanced", _, _) do
    path = Path.join(c.root, "offline")
    git(c.source, ["worktree", "add", "--detach", path, c.base])
    File.write!(Path.join(path, "offline.txt"), "offline change\n")
    git(path, ["add", "offline.txt"])
    git(path, ["commit", "-m", "offline change"])
    target = git(path, ["rev-parse", "HEAD"])
    git(c.source, ["update-ref", "refs/heads/main", target, c.base])
    target
  end

  defp change_offline(c, "rewritten", _, _) do
    tree = git(c.source, ["rev-parse", c.base <> "^{tree}"])
    target = git(c.source, ["commit-tree", tree, "-m", "rewritten root"])
    git(c.source, ["update-ref", "refs/heads/main", target, c.base])
    target
  end

  defp assert_published(c, drift, final, check, review, offline_target) do
    assert final["batch"]["status"] == "completed"
    [done] = final["deliveries"]
    assert done["status"] == "done"
    assert Enum.map(final["tasks"], & &1["state"]) == ["done"]
    sha = done["integration_intent"]["candidate_commit"]
    publish = Enum.find(final["steps"], &(&1["kind"] == "publish"))
    postcheck = Enum.find(final["steps"], &(&1["kind"] == "post_check"))
    assert postcheck["input"]["publish_step_id"] == publish["id"]
    assert postcheck["receipt"]["status"] == "finished"
    assert postcheck["receipt"]["candidate_commit"] == sha
    target = done["integration_intent"]["path"]
    assert git(c.source, ["rev-parse", "main"]) == sha
    assert git(target, ["rev-parse", "HEAD"]) == sha
    assert git(target, ["branch", "--show-current"]) == ""
    assert git(target, ["status", "--porcelain"]) == ""
    steps = Enum.sort_by(final["steps"], & &1["number"]) |> Enum.map(& &1["kind"])

    if drift == "advanced" do
      merge = Enum.find(final["steps"], &(&1["kind"] == "merge"))
      fresh_check = Enum.find(final["steps"], &(&1["kind"] == "merge_check"))
      fresh_review = Enum.find(final["steps"], &(&1["kind"] == "merge_review"))
      fresh = merge["receipt"]["workspace"]
      original = check["input"]["workspace"]
      approved = review["input"]["candidate_commit"]
      assert sha != approved and sha != offline_target

      assert git(target, ["rev-list", "--parents", "-n", "1", sha]) ==
               "#{sha} #{offline_target} #{approved}"

      assert File.read!(Path.join(target, "offline.txt")) == "offline change\n"
      assert File.read!(Path.join(target, "result.txt")) == "candidate-1\n"
      for key <- ~w(check_id path ref), do: refute(fresh[key] == original[key])
      assert git(fresh["path"], ["rev-parse", "HEAD"]) == sha
      assert git(c.source, ["rev-parse", fresh["ref"]]) == sha
      assert git(fresh["path"], ["status", "--porcelain"]) == ""
      assert fresh_check["input"]["workspace"] == fresh
      assert fresh_check["input"]["merge_step_id"] == merge["id"]
      assert fresh_check["status"] == "finished"
      assert fresh_check["receipt"]["candidate_commit"] == sha
      assert fresh_review["input"]["merge_check_step_id"] == fresh_check["id"]
      assert fresh_review["input"]["original_review_step_id"] == review["id"]
      assert fresh_review["receipt"]["candidate_commit"] == sha
      assert fresh_review["status"] == "finished"
      assert fresh_review["receipt"]["report"]["verdict"] == "approved"
      assert publish["input"]["review_step_id"] == fresh_review["id"]

      assert steps ==
               ~w(plan implement snapshot check review merge merge_check merge_review publish post_check)

      assert calls(c.root, "calls") == ~w(plan implement review merge_review)
      assert calls(c.root, "check-calls") == [original["path"], fresh["path"], target]
    else
      assert sha == review["input"]["candidate_commit"]
      assert publish["input"]["review_step_id"] == review["id"]
      assert steps == ~w(plan implement snapshot check review publish post_check)
      assert calls(c.root, "calls") == ~w(plan implement review)
      assert calls(c.root, "check-calls") == [check["input"]["workspace"]["path"], target]
    end
  end

  defp boot(root, boundary, mode) do
    fixture = Path.expand("../fixtures/boss_backend_recovery.exs", __DIR__)
    libraries = Path.join(Path.dirname(Application.app_dir(:boss)), "*/ebin")

    vm =
      Port.open({:spawn_executable, System.find_executable("elixir")}, [
        :binary,
        :exit_status,
        :stderr_to_stdout,
        args: ["--erl", "+S 2:2", "-pa", libraries, fixture, root, boundary, mode]
      ])

    {:os_pid, pid} = Port.info(vm, :os_pid)
    started = process_field(pid, "lstart=")

    on_exit(fn ->
      # The test's Port owner may already be gone; retain start identity plus its unique argv.
      cleanup_vm(pid, started, root, fixture)

      try do
        Port.close(vm)
      rescue
        ArgumentError -> :ok
      end
    end)

    vm
  end

  defp kill_vm(vm) do
    # A live Port retains the identity of this child; a saved PID alone is insufficient.
    case Port.info(vm, :os_pid) do
      {:os_pid, pid} -> System.cmd("/bin/kill", ["-KILL", to_string(pid)], stderr_to_stdout: true)
      nil -> :ok
    end
  end

  defp wait_json(root, name, vm, attempts \\ 2500, output \\ "")
  defp wait_json(_, name, _, 0, output), do: flunk("No #{name} checkpoint: #{output}")

  defp wait_json(root, name, vm, attempts, output) do
    if File.exists?(Path.join(root, name <> ".json")) do
      read_json(root, name)
    else
      receive do
        {^vm, {:data, data}} ->
          combined = output <> data

          output =
            binary_part(
              combined,
              max(0, byte_size(combined) - 4096),
              min(byte_size(combined), 4096)
            )

          wait_json(root, name, vm, attempts - 1, output)

        {^vm, {:exit_status, status}} ->
          if File.exists?(Path.join(root, name <> ".json")) do
            send(self(), {vm, {:exit_status, status}})
            read_json(root, name)
          else
            flunk("Backend exited #{status} before #{name}: #{output}")
          end
      after
        20 -> wait_json(root, name, vm, attempts - 1, output)
      end
    end
  end

  defp read_json(root, name),
    do: root |> Path.join(name <> ".json") |> File.read!() |> JSON.decode!()

  defp calls(root, name) do
    case File.read(Path.join(root, name)) do
      {:ok, contents} -> String.split(contents, "\n", trim: true)
      {:error, :enoent} -> []
    end
  end

  defp git(source, args) do
    {output, status} =
      System.cmd("git", args,
        cd: source,
        stderr_to_stdout: true,
        env: [{"GIT_CONFIG_GLOBAL", "/dev/null"}, {"GIT_CONFIG_NOSYSTEM", "1"}]
      )

    assert status == 0, inspect({args, output})
    String.trim(output)
  end

  defp identity(pid) do
    process_field(pid, "lstart=,command=")
  end

  defp process_field(pid, field) do
    case System.cmd("/bin/ps", ["-p", to_string(pid), "-o", field], stderr_to_stdout: true) do
      {text, 0} -> String.trim(text)
      _ -> nil
    end
  end

  defp cleanup_vm(pid, started, root, fixture) do
    owned? = fn ->
      command = process_field(pid, "command=")

      started != nil and process_field(pid, "lstart=") == started and
        is_binary(command) and String.contains?(command, root) and
        String.contains?(command, fixture)
    end

    if owned?.() do
      System.cmd("/bin/kill", ["-KILL", to_string(pid)], stderr_to_stdout: true)
      eventually(fn -> not owned?.() or not alive?(pid) end, 250)
    end
  end

  defp alive?(pid) do
    case System.cmd("/bin/ps", ["-p", to_string(pid), "-o", "stat="], stderr_to_stdout: true) do
      {status, 0} -> not String.contains?(status, "Z")
      _ -> false
    end
  end

  defp cleanup_owned(identities) do
    for {pid, expected} <- identities,
        expected != nil,
        identity(pid) == expected,
        do: System.cmd("/bin/kill", ["-KILL", to_string(pid)], stderr_to_stdout: true)

    eventually(
      fn ->
        Enum.all?(identities, fn {pid, expected} ->
          identity(pid) != expected or not alive?(pid)
        end)
      end,
      250
    )
  end

  defp eventually(predicate, attempts)
  defp eventually(_, 0), do: flunk("Owned process group outlived the backend")

  defp eventually(predicate, attempts) do
    if predicate.() do
      :ok
    else
      Process.sleep(20)
      eventually(predicate, attempts - 1)
    end
  end
end
