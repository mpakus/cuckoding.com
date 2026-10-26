defmodule Boss.Projects.SpecWatcherTest do
  use Boss.DataCase
  alias Boss.Projects
  alias Boss.Projects.{SpecImporter, SpecWatcher}
  import ExUnit.CaptureLog

  setup do
    root =
      Path.join(
        System.tmp_dir!(),
        "boss-watch-#{Base.url_encode64(:crypto.strong_rand_bytes(12), padding: false)}"
      )

    File.mkdir!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    %{root: root}
  end

  test "status and reporting tolerate a stopped watcher" do
    assert SpecWatcher.status(123) == nil
    assert SpecWatcher.report(123, {:ok, counts()}) == :ok
  end

  test "reports broadcast every success and suppress only repeated identical errors" do
    start_watcher(interval_ms: 60_000)
    :ok = SpecWatcher.subscribe(123)
    result = {:ok, counts()}
    assert :ok = SpecWatcher.report(123, result)
    assert SpecWatcher.status(123) == result
    assert_receive {:spec_sync, 123, ^result}
    assert :ok = SpecWatcher.report(123, result)
    assert_receive {:spec_sync, 123, ^result}
    error = {:error, [%{path: "broken.md", message: "Invalid YAML."}]}
    assert :ok = SpecWatcher.report(123, error)
    assert_receive {:spec_sync, 123, ^error}
    assert SpecWatcher.status(123) == error
    assert :ok = SpecWatcher.report(123, error)
    refute_receive {:spec_sync, 123, _}, 30
    assert :ok = SpecWatcher.report(123, result)
    assert_receive {:spec_sync, 123, ^result}
  end

  test "startup scans and later edits append revisions without changing the task snapshot", %{
    root: root
  } do
    project = project(root, "one")
    path = Path.join(project.specs_path, "one.md")
    File.write!(path, "# First")
    :ok = SpecWatcher.subscribe(project.id)
    start_watcher()
    id = project.id
    assert_receive {:spec_sync, ^id, {:ok, %{created: 1}}}, 2000
    [entry] = Projects.list_spec_entries(id)
    File.write!(path, "# Edited")
    assert_receive {:spec_sync, ^id, {:ok, %{revised: 1}}}, 2000
    assert [updated] = Projects.list_spec_entries(id)
    assert updated.id == entry.id
    assert updated.latest_revision == 2
    assert updated.task_revision == 1
    assert updated.title == "First"
  end

  test "projects registered after startup join the next sweep", %{root: root} do
    start_watcher()
    project = project(root, "late")
    :ok = SpecWatcher.subscribe(project.id)
    File.write!(Path.join(project.specs_path, "late.md"), "# Added later")
    id = project.id
    assert_receive {:spec_sync, ^id, {:ok, %{created: 1}}}, 2000
    assert [%{title: "Added later"}] = Projects.list_spec_entries(id)
  end

  test "a burst between observations is retried without importing intermediate text", %{
    root: root
  } do
    project = project(root, "burst")
    path = Path.join(project.specs_path, "one.md")
    File.write!(path, "# Original")
    assert {:ok, _} = SpecImporter.sync(project.id)
    File.write!(path, "# Intermediate")
    gate = gate_snapshot()
    :ok = SpecWatcher.subscribe(project.id)
    start_watcher(settle_ms: 50)
    assert_receive {^gate, importer}, 2000
    File.write!(path, "# Final")
    :telemetry.detach(gate)
    send(importer, {:continue, gate})
    id = project.id
    assert_receive {:spec_sync, ^id, {:error, _}}, 2000
    assert_receive {:spec_sync, ^id, {:ok, %{revised: 1}}}, 2000
    [entry] = Projects.list_spec_entries(id)

    assert Enum.map(Projects.list_spec_revisions(entry.id), & &1.original_text) == [
             "# Original",
             "# Final"
           ]
  end

  test "an unavailable directory retains history and is retried when restored", %{root: root} do
    project = project(root, "retry")
    File.write!(Path.join(project.specs_path, "one.md"), "# Retained")
    assert {:ok, _} = SpecImporter.sync(project.id)
    File.rename!(project.specs_path, project.specs_path <> "-away")
    :ok = SpecWatcher.subscribe(project.id)
    start_watcher()
    id = project.id
    assert_receive {:spec_sync, ^id, {:error, _}}, 2000
    assert [%{missing: false, latest_revision: 1}] = Projects.list_spec_entries(id)
    File.rename!(project.specs_path <> "-away", project.specs_path)
    assert_receive {:spec_sync, ^id, {:ok, %{unchanged: 1, missing: 0}}}, 2000
    assert [%{latest_revision: 1}] = Projects.list_spec_entries(id)
  end

  test "slow sweeps do not overlap and killing their owner stops the remaining projects", %{
    root: root
  } do
    first = project(root, "first")
    second = project(root, "second")
    File.write!(Path.join(first.specs_path, "one.md"), "# First")
    File.write!(Path.join(second.specs_path, "two.md"), "# Second")
    gate = gate_snapshot()
    watcher = start_watcher(interval_ms: 10, settle_ms: 50)
    assert_receive {^gate, importer}, 2000
    worker = :sys.get_state(watcher).task.pid
    worker_monitor = Process.monitor(worker)
    for _ <- 1..5, do: send(watcher, :sweep)
    Process.sleep(80)
    assert length(Task.Supervisor.children(Boss.SpecImportSupervisor)) == 1
    assert :sys.get_state(watcher).task.pid == worker
    Process.exit(watcher, :kill)
    assert_receive {:DOWN, ^worker_monitor, :process, ^worker, _}, 1000
    :telemetry.detach(gate)
    send(importer, {:continue, gate})
    await_no_imports()
    assert Projects.list_spec_entries(second.id) == []
    assert SpecWatcher.status(first.id) == nil
  end

  test "restarting the watcher rescans without duplicate history", %{root: root} do
    project = project(root, "restart")
    File.write!(Path.join(project.specs_path, "one.md"), "# Stable")
    :ok = SpecWatcher.subscribe(project.id)
    start_watcher(interval_ms: 60_000)
    id = project.id
    assert_receive {:spec_sync, ^id, {:ok, %{created: 1}}}, 2000
    assert :ok = stop_supervised(SpecWatcher)
    start_watcher(interval_ms: 60_000)
    assert_receive {:spec_sync, ^id, {:ok, %{unchanged: 1}}}, 2000
    assert [%{latest_revision: 1, task_revision: 1}] = Projects.list_spec_entries(id)
  end

  test "project-list database failures are paced rather than restarting the watcher" do
    {dead_repo, monitor} = spawn_monitor(fn -> :ok end)
    assert_receive {:DOWN, ^monitor, :process, ^dead_repo, _}

    log =
      capture_log(fn ->
        watcher = start_watcher(repo: dead_repo, interval_ms: 150)
        Process.sleep(380)
        assert Process.alive?(watcher)
        assert :ok = stop_supervised(SpecWatcher)
      end)

    warnings = length(Regex.scan(~r/Automatic spec sweep could not complete/, log))
    assert warnings in 2..3
  end

  test "invalid timing options are rejected instead of creating a hot loop" do
    for opts <- [[interval_ms: 0], [interval_ms: -1], [settle_ms: -1], [settle_ms: 1001]] do
      assert {:error, :invalid_timing_options} = SpecWatcher.start_link(opts)
    end
  end

  defp start_watcher(opts \\ []) do
    opts = Keyword.merge([interval_ms: 40, settle_ms: 20], opts)
    start_supervised!(Supervisor.child_spec({SpecWatcher, opts}, restart: :temporary))
  end

  defp project(root, name) do
    path = Path.join(root, name)
    File.mkdir!(path)
    File.mkdir!(Path.join(path, "specs"))
    {_, 0} = System.cmd("git", ["-C", path, "init", "-b", "main"])

    {_, 0} =
      System.cmd("git", [
        "-C",
        path,
        "-c",
        "user.name=Test",
        "-c",
        "user.email=test@example.invalid",
        "commit",
        "--allow-empty",
        "-m",
        "base"
      ])

    {:ok, project} = Projects.create_project(%{root_path: path})
    project
  end

  defp gate_snapshot do
    ref = make_ref()
    owner = self()

    :ok =
      :telemetry.attach(
        ref,
        [:boss, :repo, :query],
        fn _, _, metadata, _ ->
          if metadata.source == "specs" and String.contains?(metadata.query, "original_text") do
            send(owner, {ref, self()})

            receive do
              {:continue, ^ref} -> :ok
            after
              3000 -> :ok
            end
          end
        end,
        nil
      )

    on_exit(fn -> :telemetry.detach(ref) end)
    ref
  end

  defp await_no_imports(attempts \\ 100)
  defp await_no_imports(0), do: flunk("Import workers did not finish")

  defp await_no_imports(attempts) do
    if Task.Supervisor.children(Boss.SpecImportSupervisor) != [] do
      Process.sleep(10)
      await_no_imports(attempts - 1)
    end
  end

  defp counts, do: %{created: 0, revised: 0, unchanged: 0, missing: 0}
end
