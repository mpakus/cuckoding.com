defmodule Boss.DeliveryReviewerPersistenceTest do
  use ExUnit.Case, async: false
  alias Boss.{Deliveries, Projects, Repo, Tasks}
  @moduletag capture_log: true
  @version 20_261_027_030_000
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
    {20_261_027_060_000, Boss.Repo.Migrations.AddDeliveryScheduling}
  ]

  test "migration preserves Codex history and pinned Claude request survives restart" do
    root = Path.join(System.tmp_dir!(), "boss-reviewer-#{Ecto.UUID.generate()}")
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
    migrations = @migrations
    Ecto.Migrator.run(Repo, migrations, :up, to: @version - 10_000, log: false)

    project =
      Repo.insert!(%Projects.Project{
        name: "Reviewer",
        root_path: root,
        git_common_dir: Path.join(root, ".git"),
        specs_path: root,
        base_branch: "main"
      })

    {:ok, %{task: task}} =
      Projects.record_spec(project.id, %{
        relative_path: "one.md",
        title: "One",
        original_text: "# One"
      })

    legacy_id = Ecto.UUID.generate()
    {:ok, config, hash} = Boss.Checks.Command.parse("true")

    Repo.query!(
      """
      INSERT INTO deliveries(id,project_id,task_id,spec_revision_id,command_id,
        admitted_version,task_version,check_config,config_hash,inserted_at,updated_at)
      VALUES(?,?,?,?,?,0,0,?,?,CURRENT_TIMESTAMP,CURRENT_TIMESTAMP)
      """,
      [
        legacy_id,
        project.id,
        task.id,
        task.spec_revision_id,
        Ecto.UUID.generate(),
        JSON.encode!(config),
        hash
      ]
    )

    Ecto.Migrator.run(Repo, migrations, :up, all: true, log: false)
    assert Deliveries.get(project.id, legacy_id).reviewer == "codex"
    assert {:ok, _} = Deliveries.complete(legacy_id, "cancelled")

    # A reversible empty-Claude downgrade also proves the new trigger has no stale references.
    Ecto.Migrator.run(Repo, migrations, :down, to: @version, log: false)
    Ecto.Migrator.run(Repo, migrations, :up, all: true, log: false)
    assert Deliveries.get(project.id, legacy_id).reviewer == "codex"

    command = Ecto.UUID.generate()

    assert {:ok, {:new, saved}} =
             Deliveries.admit(project.id, task.id, command, "true", "claude", false)

    :ok = stop_supervised(Repo)
    repo = start_supervised!({Repo, opts})
    Repo.put_dynamic_repo(repo)

    assert {:ok, {:existing, ^saved}} =
             Deliveries.admit(project.id, task.id, command, "true", "claude", true)

    assert {:error, :idempotency_conflict} =
             Deliveries.admit(project.id, task.id, command, "true")

    assert Deliveries.steps(saved.id) == []
    assert Tasks.get_task!(task.id).state == "planning"

    assert_raise RuntimeError, "Refusing to discard Claude reviewer history", fn ->
      Ecto.Migrator.run(Repo, migrations, :down, to: @version, log: false)
    end

    assert Deliveries.get(project.id, saved.id).reviewer == "claude"

    assert {:error, _} =
             Repo.query("UPDATE deliveries SET reviewer='codex' WHERE id=?", [saved.id])

    assert {:ok, [%Deliveries.Delivery{id: interrupted_id}]} = Deliveries.reconcile()
    assert interrupted_id == saved.id
    interrupted = Deliveries.get(project.id, saved.id)
    assert interrupted.reviewer == "claude"
    assert interrupted.cleanup == "unknown"

    assert {:ok, {:existing, ^interrupted}} =
             Deliveries.admit(project.id, task.id, command, "true", "claude", true)
  end
end
