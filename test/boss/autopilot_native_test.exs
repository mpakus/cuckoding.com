defmodule Boss.AutopilotNativeTest do
  use ExUnit.Case, async: false
  alias Boss.{Deliveries, Projects, Repo, Tasks}
  alias Boss.Deliveries.{Autopilot, AutopilotBatch}
  alias Boss.Runs.Manager
  @moduletag skip: :os.type() != {:unix, :darwin}
  @moduletag capture_log: true
  @moduletag timeout: 120_000
  @registry Boss.AutopilotNativeActive
  @migrations [
    {20_261_025_180_000, Boss.Repo.Migrations.CreateProjects},
    {20_261_025_220_000, Boss.Repo.Migrations.CreateSpecRevisions},
    {20_261_025_230_000, Boss.Repo.Migrations.TrackMissingSpecs},
    {20_261_026_010_000, Boss.Repo.Migrations.CreateTaskEvents},
    {20_261_026_040_000, Boss.Repo.Migrations.CreateAgentRuns},
    {20_261_026_060_000, Boss.Repo.Migrations.AddManualChecks},
    {20_261_026_160_000, Boss.Repo.Migrations.AddManualReviews},
    {20_261_026_220_000, Boss.Repo.Migrations.CreateDeliveries},
    {20_261_027_010_000, Boss.Repo.Migrations.AddTaskRevisionAdoption},
    {20_261_027_020_000, Boss.Repo.Migrations.PreserveHistoricalRunPins},
    {20_261_027_030_000, Boss.Repo.Migrations.PinDeliveryReviewer},
    {20_261_027_040_000, Boss.Repo.Migrations.AddWorkflowQueue},
    {20_261_027_050_000, Boss.Repo.Migrations.AddMergeIntegrationEvidence},
    {20_261_027_060_000, Boss.Repo.Migrations.AddDeliveryScheduling},
    {20_261_027_070_000, Boss.Repo.Migrations.AddAutopilot}
  ]

  setup do
    root = Path.join(System.tmp_dir!(), "boss-autopilot-native-#{Ecto.UUID.generate()}")
    File.mkdir!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    {:ok, lock} = Boss.DataDirectory.acquire(root)
    on_exit(fn -> Boss.DataDirectory.release(lock) end)
    old_data = Application.fetch_env!(:boss, :data_dir)
    Application.put_env(:boss, :data_dir, root)
    on_exit(fn -> Application.put_env(:boss, :data_dir, old_data) end)

    opts = [
      name: nil,
      database: Path.join(root, "boss.db"),
      pool: DBConnection.ConnectionPool,
      pool_size: 2
    ]

    repo = start_repo(opts)
    Repo.put_dynamic_repo(repo)
    Ecto.Migrator.run(Repo, @migrations, :up, all: true, log: false)
    source = Path.join(root, "source")
    File.mkdir!(source)
    {physical, 0} = System.cmd("/bin/pwd", ["-P"], cd: source)
    source = String.trim(physical)
    File.write!(Path.join(source, "result.txt"), "base")
    File.cp!(Path.expand("../fixtures/delivery_check.py", __DIR__), Path.join(source, "check.py"))

    for args <- [
          ["init", "-b", "main"],
          ["config", "user.name", "Fixture"],
          ["config", "user.email", "fixture@example.invalid"],
          ["add", "."],
          ["commit", "-m", "base"]
        ],
        do: git(source, args)

    git(source, ["switch", "-c", "user-work"])

    project =
      Repo.insert!(%Projects.Project{
        name: "Native Autopilot",
        root_path: source,
        git_common_dir: Path.join(source, ".git"),
        specs_path: source,
        base_branch: "main"
      })

    tasks =
      for name <- ~w(one two) do
        {:ok, record} =
          Projects.record_spec(project.id, %{
            relative_path: "#{name}.md",
            explicit_id: name,
            title: name,
            original_text:
              "---\nid: #{name}\n#{if name == "two", do: "depends_on: [one]\n", else: ""}---\n# #{name}\nCreate result.txt"
          })

        record.task
      end

    gates = Path.join(root, "gates")
    bin = Path.join(root, "bin")
    File.mkdir!(gates)
    File.mkdir!(bin)
    File.cp!(Path.expand("../fixtures/codex_autopilot.py", __DIR__), Path.join(bin, "codex"))
    File.chmod!(Path.join(bin, "codex"), 0o700)

    env = %{
      "PATH" => bin <> ":" <> System.fetch_env!("PATH"),
      "BOSS_AUTOPILOT_GATES" => gates,
      "BOSS_DELIVERY_FIXTURE" => root,
      "BOSS_AUTOPILOT_MODE" => "approved"
    }

    previous = Map.take(System.get_env(), Map.keys(env))
    System.put_env(env)

    on_exit(fn ->
      for key <- Map.keys(env) do
        if Map.has_key?(previous, key),
          do: System.put_env(key, previous[key]),
          else: System.delete_env(key)
      end
    end)

    %{
      root: root,
      gates: gates,
      repo: repo,
      opts: opts,
      source: source,
      project: project,
      tasks: tasks
    }
  end

  test "all Backlog tasks integrate sequentially; dependency sees actual Done and retained target",
       c do
    manager = start_manager(c.repo)
    original = git(c.source, ["rev-parse", "HEAD"])
    command = Ecto.UUID.generate()
    ids = Enum.reverse(Enum.map(c.tasks, & &1.id))

    {:ok, batch} =
      Autopilot.start(c.project.id, command, ids, "python3 check.py", "codex", manager)

    one = wait_for_implementation(c, "one", 1)
    assert Repo.aggregate(Deliveries.Delivery, :count) == 1

    assert {:ok, replay} =
             Autopilot.start(c.project.id, command, ids, "python3 check.py", "codex", manager)

    assert replay.id == batch.id
    assert :sys.get_state(manager).active |> map_size() == 1
    release(c, "one", 1)
    two = wait_for_implementation(c, "two", 1)
    [first, second] = c.tasks
    assert Repo.get!(Tasks.Task, first.id).state == "done"
    done = Deliveries.get(c.project.id, one.id)
    assert done.status == "done"
    assert two.intent["base_commit"] == done.integration_intent["candidate_commit"]
    refute two.intent["base_commit"] == original
    release(c, "two", 1)
    eventually(fn -> Repo.get!(AutopilotBatch, batch.id).status == "completed" end, 3000)
    assert Repo.get!(Tasks.Task, second.id).state == "done"
    assert Repo.aggregate(Deliveries.Delivery, :count) == 2

    for d <- Repo.all(Deliveries.Delivery) do
      assert d.cleanup == "group_empty"

      assert Enum.map(Deliveries.steps(d.id), & &1.kind) ==
               ~w(plan implement snapshot check review publish post_check)

      assert d.integration_command_id != nil
    end

    assert git(c.source, ["branch", "--show-current"]) == "user-work"
    assert git(c.source, ["rev-parse", "HEAD"]) == original
    assert git(c.source, ["status", "--porcelain"]) == ""

    assert {:ok, replay} =
             Autopilot.start(c.project.id, command, ids, "python3 check.py", "codex", manager)

    assert replay.status == "completed"
  end

  test "review rejection returns to implementation and automatic publication waits for the repaired candidate",
       c do
    System.put_env("BOSS_AUTOPILOT_MODE", "repair")
    manager = start_manager(c.repo)

    {:ok, batch} =
      Autopilot.start(
        c.project.id,
        Ecto.UUID.generate(),
        Enum.map(c.tasks, & &1.id),
        "python3 check.py",
        "codex",
        manager
      )

    one = wait_for_implementation(c, "one", 1)
    release(c, "one", 1)
    fixed = wait_for_implementation(c, "one", 2)
    assert fixed.id == one.id
    assert Repo.aggregate(Deliveries.Delivery, :count) == 1
    assert Deliveries.get(c.project.id, one.id).integration_command_id == nil
    release(c, "one", 2)
    wait_for_implementation(c, "two", 1)
    assert Deliveries.get(c.project.id, one.id).status == "done"
    assert Deliveries.get(c.project.id, one.id).cycle == 2
    {:ok, current} = Autopilot.current(c.project.id)
    assert {:ok, _} = Autopilot.cancel(c.project.id, batch.id, current.version, @registry)
    eventually(fn -> :sys.get_state(manager).active == %{} end)
    refute Repo.get!(Tasks.Task, List.last(c.tasks).id).state == "done"
  end

  test "checked-out target blocks before any model and failed plan stops the remaining tasks",
       c do
    git(c.source, ["switch", "main"])
    manager = start_manager(c.repo)
    ids = Enum.map(c.tasks, & &1.id)

    {:ok, batch} =
      Autopilot.start(
        c.project.id,
        Ecto.UUID.generate(),
        ids,
        "python3 check.py",
        "codex",
        manager
      )

    eventually(fn -> Repo.get!(AutopilotBatch, batch.id).status == "blocked" end)
    assert Repo.get!(AutopilotBatch, batch.id).reason =~ "checked out"
    refute File.exists?(Path.join(c.root, "calls"))
    assert Repo.aggregate(Deliveries.Delivery, :count) == 0
    git(c.source, ["switch", "user-work"])
    System.put_env("BOSS_AUTOPILOT_MODE", "invalid")

    {:ok, failed} =
      Autopilot.start(
        c.project.id,
        Ecto.UUID.generate(),
        ids,
        "python3 check.py",
        "codex",
        manager
      )

    eventually(fn -> Repo.get!(AutopilotBatch, failed.id).status == "blocked" end)
    assert Repo.aggregate(Deliveries.Delivery, :count) == 1
    assert Repo.get!(Tasks.Task, List.last(c.tasks).id).state == "new"

    assert File.read!(Path.join(c.root, "calls")) |> String.split("\n", trim: true) |> length() ==
             1
  end

  defp wait_for_implementation(c, name, cycle) do
    eventually(fn -> File.exists?(Path.join(c.gates, "#{name}-#{cycle}.waiting")) end, 3000)
    task = Enum.find(c.tasks, &(&1.title == name))
    import Ecto.Query

    Repo.one!(
      from d in Deliveries.Delivery, where: d.task_id == ^task.id and d.status == "implementing"
    )
  end

  defp release(c, name, cycle),
    do: File.write!(Path.join(c.gates, "#{name}-#{cycle}.release"), "")

  defp start_repo(opts),
    do: start_supervised!(Supervisor.child_spec({Repo, opts}, restart: :temporary))

  defp start_manager(repo),
    do:
      start_supervised!(
        Supervisor.child_spec({Manager, [name: nil, registry: @registry, repo: repo]},
          restart: :temporary
        )
      )

  defp git(path, args) do
    {output, status} =
      System.cmd("git", args,
        cd: path,
        stderr_to_stdout: true,
        env: [{"GIT_CONFIG_GLOBAL", "/dev/null"}, {"GIT_CONFIG_NOSYSTEM", "1"}]
      )

    assert status == 0, inspect({args, output})
    String.trim(output)
  end

  defp eventually(predicate, left \\ 1500)
  defp eventually(_, 0), do: flunk("Autopilot did not settle within fixture deadline")

  defp eventually(predicate, left) do
    if predicate.(),
      do: :ok,
      else:
        (
          Process.sleep(20)
          eventually(predicate, left - 1)
        )
  end
end
