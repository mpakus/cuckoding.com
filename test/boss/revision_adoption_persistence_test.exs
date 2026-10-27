defmodule Boss.RevisionAdoptionPersistenceTest do
  use ExUnit.Case, async: false
  alias Boss.{Projects, Repo, Runs, Tasks}
  @moduletag capture_log: true
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
    {20_261_027_040_000, Boss.Repo.Migrations.AddWorkflowQueue}
  ]

  setup do
    root = Path.join(System.tmp_dir!(), "boss-adoption-#{Ecto.UUID.generate()}")
    File.mkdir!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    {:ok, lock} = Boss.DataDirectory.acquire(root)
    on_exit(fn -> Boss.DataDirectory.release(lock) end)

    opts = [
      name: nil,
      database: Path.join(root, "boss.db"),
      pool: DBConnection.ConnectionPool,
      pool_size: 2
    ]

    repo = start_supervised!({Repo, opts})
    Repo.put_dynamic_repo(repo)
    Ecto.Migrator.run(Repo, @migrations, :up, all: true, log: false)

    project =
      Repo.insert!(%Projects.Project{
        name: "Adoption",
        root_path: root,
        git_common_dir: Path.join(root, ".git"),
        specs_path: root,
        base_branch: "main"
      })

    {:ok, first} = record(project.id, "# First")
    {:ok, second} = record(project.id, "# Second")

    command = %{
      command_id: Ecto.UUID.generate(),
      expected_version: 0,
      action: "adopt_revision",
      project_id: project.id,
      spec_revision_id: second.revision.id
    }

    %{repo: repo, opts: opts, project: project, first: first, second: second, command: command}
  end

  test "committed adoption receipt survives later adoption and a Repo restart", c do
    Tasks.subscribe(c.project.id)
    assert {:ok, receipt} = Tasks.transition(c.first.task.id, c.command)
    assert_receive {:task_changed, project_id}
    assert project_id == c.project.id
    assert Repo.get!(Tasks.Event, receipt.id) == receipt
    {:ok, third} = record(c.project.id, "# Third")

    assert {:ok, _} =
             Tasks.transition(c.first.task.id, %{
               c.command
               | command_id: Ecto.UUID.generate(),
                 expected_version: 1,
                 spec_revision_id: third.revision.id
             })

    :ok = stop_supervised(Repo)
    repo = start_supervised!({Repo, c.opts})
    Repo.put_dynamic_repo(repo)
    assert {:ok, ^receipt} = Tasks.transition(c.first.task.id, c.command)
    assert Tasks.get_task!(c.first.task.id).spec_revision_id == third.revision.id
    assert length(Tasks.list_events(c.first.task.id)) == 2
  end

  test "duplicate concurrent commands create one task version and one immutable receipt", c do
    results =
      concurrent(
        c.repo,
        Enum.map(1..4, fn _ -> fn -> Tasks.transition(c.first.task.id, c.command) end end)
      )

    assert [{:ok, event}] = Enum.uniq(results)
    assert Tasks.list_events(c.first.task.id) == [event]
    assert Tasks.get_task!(c.first.task.id).state_version == 1
  end

  test "different target revisions racing the same version cannot both advance the task", c do
    {:ok, third} = record(c.project.id, "# Third")
    other = %{c.command | command_id: Ecto.UUID.generate(), spec_revision_id: third.revision.id}

    results =
      concurrent(c.repo, [
        fn -> Tasks.transition(c.first.task.id, c.command) end,
        fn -> Tasks.transition(c.first.task.id, other) end
      ])

    assert Enum.count(results, &match?({:ok, _}, &1)) == 1
    assert {:error, :stale_state} in results
    assert [event] = Tasks.list_events(c.first.task.id)
    assert Tasks.get_task!(c.first.task.id).spec_revision_id == event.target_spec_revision_id
  end

  test "adoption racing manual admission cannot rebind an admitted attempt", c do
    results =
      concurrent(c.repo, [
        fn -> Tasks.transition(c.first.task.id, c.command) end,
        fn -> Runs.admit(c.project.id, c.first.task.id, Ecto.UUID.generate()) end
      ])

    assert [run] = Repo.all(Runs.Run)
    task = Tasks.get_task!(c.first.task.id)
    assert run.spec_revision_id == task.spec_revision_id
    assert run.admitted_version == task.state_version
    assert Enum.any?(results, &match?({:ok, {:new, _}}, &1))

    if task.spec_revision_id == c.first.revision.id do
      assert {:error, :busy} in results
      assert Tasks.list_events(task.id) == []
    else
      assert task.spec_revision_id == c.second.revision.id
      assert length(Tasks.list_events(task.id)) == 1
    end
  end

  test "unrelated active work does not block task metadata and nested rollback stays silent", c do
    {:ok, other} =
      Projects.record_spec(c.project.id, %{
        relative_path: "other.md",
        title: "Other",
        original_text: "# Other"
      })

    {:ok, {:new, _}} = Runs.admit(c.project.id, other.task.id, Ecto.UUID.generate())
    Tasks.subscribe(c.project.id)

    assert {:error, :rollback} =
             Repo.transaction(
               fn ->
                 assert {:ok, _} = Tasks.transition(c.first.task.id, c.command)
                 refute_receive {:task_changed, _}, 20
                 Repo.rollback(:rollback)
               end,
               mode: :immediate
             )

    assert Tasks.get_task!(c.first.task.id) == c.first.task
    assert {:ok, _} = Tasks.transition(c.first.task.id, c.command)
    assert_receive {:task_changed, _}
  end

  test "migration downgrade cannot discard adoption receipt or invalidate old verification pins",
       c do
    assert {:ok, receipt} = Tasks.transition(c.first.task.id, c.command)

    assert_raise Ecto.MigrationError, "cannot invalidate historical verification pins", fn ->
      Ecto.Migrator.run(
        Repo,
        [{20_261_027_020_000, Boss.Repo.Migrations.PreserveHistoricalRunPins}],
        :down,
        all: true,
        log: false
      )
    end

    assert_raise Ecto.MigrationError, "cannot discard retained task events", fn ->
      Ecto.Migrator.run(
        Repo,
        [{20_261_027_010_000, Boss.Repo.Migrations.AddTaskRevisionAdoption}],
        :down,
        all: true,
        log: false
      )
    end

    assert {:ok, ^receipt} = Tasks.transition(c.first.task.id, c.command)

    assert {:error, _} =
             Repo.query("UPDATE task_events SET target_spec_revision_id=NULL WHERE id=?", [
               receipt.id
             ])

    assert {:error, _} = Repo.query("DELETE FROM task_events WHERE id=?", [receipt.id])

    assert {:error, _} =
             Repo.query(
               "INSERT INTO task_events(task_id,spec_revision_id,target_spec_revision_id,command_id,version,action,from_state,to_state,inserted_at) VALUES(?,?,?,?,?,'adopt_revision','new','new',?)",
               [
                 c.first.task.id,
                 c.first.revision.id,
                 c.first.revision.id,
                 Ecto.UUID.generate(),
                 2,
                 DateTime.to_iso8601(DateTime.utc_now())
               ]
             )

    assert Tasks.list_events(c.first.task.id) == [receipt]
  end

  defp concurrent(repo, jobs),
    do:
      jobs
      |> Task.async_stream(
        fn job ->
          Repo.put_dynamic_repo(repo)
          job.()
        end,
        max_concurrency: 4,
        timeout: 10_000
      )
      |> Enum.map(fn {:ok, result} -> result end)

  defp record(project, source),
    do:
      Projects.record_spec(project, %{
        relative_path: "one.md",
        title: "Stored",
        original_text: source
      })
end
