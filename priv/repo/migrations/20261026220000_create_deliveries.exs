defmodule Boss.Repo.Migrations.CreateDeliveries do
  use Ecto.Migration

  def up do
    create table(:deliveries, primary_key: false) do
      add :id, :string, primary_key: true
      add :project_id, references(:projects, on_delete: :restrict), null: false
      add :task_id, references(:tasks, on_delete: :restrict), null: false
      add :spec_revision_id, references(:spec_revisions, on_delete: :restrict), null: false
      add :command_id, :string, null: false
      add :admitted_version, :integer, null: false
      add :task_version, :integer, null: false
      add :check_config, :map, null: false
      add :config_hash, :string, null: false
      add :status, :string, null: false, default: "planning"
      add :cycle, :integer, null: false, default: 0
      add :cleanup, :string, null: false, default: "pending"
      add :intent, :map, null: false, default: %{}
      add :integration_intent, :map, null: false, default: %{}
      add :integration_command_id, :string
      add :reason, :text
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:deliveries, [:task_id, :command_id])
    create unique_index(:deliveries, [:integration_command_id])

    active =
      "status IN ('planning','implementing','testing','reviewing','integrating') OR cleanup='unknown'"

    execute("CREATE UNIQUE INDEX deliveries_one_open ON deliveries ((1)) WHERE #{active}")

    execute(
      "CREATE UNIQUE INDEX deliveries_task_open ON deliveries (task_id) WHERE #{active} OR status='ready_to_merge'"
    )

    create table(:delivery_steps, primary_key: false) do
      add :id, :string, primary_key: true
      add :delivery_id, references(:deliveries, type: :string, on_delete: :restrict), null: false
      add :number, :integer, null: false
      add :kind, :string, null: false
      add :cycle, :integer, null: false
      add :input, :map, null: false, default: %{}
      add :receipt, :map, null: false, default: %{}
      add :status, :string, null: false, default: "running"
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:delivery_steps, [:delivery_id, :number])

    execute(
      "CREATE UNIQUE INDEX delivery_steps_one_running ON delivery_steps (delivery_id) WHERE status='running'"
    )

    execute("""
    CREATE TRIGGER delivery_pin BEFORE INSERT ON deliveries
    WHEN NEW.admitted_version!=NEW.task_version OR NOT EXISTS
      (SELECT 1 FROM tasks t JOIN specs s ON s.id=t.spec_id WHERE t.id=NEW.task_id
      AND s.project_id=NEW.project_id AND t.spec_revision_id=NEW.spec_revision_id
      AND t.state_version=NEW.task_version)
    BEGIN SELECT RAISE(ABORT, 'delivery snapshot mismatch'); END
    """)

    execute("""
    CREATE TRIGGER delivery_immutable BEFORE UPDATE ON deliveries
    WHEN OLD.id!=NEW.id OR OLD.project_id!=NEW.project_id OR OLD.task_id!=NEW.task_id
      OR OLD.spec_revision_id!=NEW.spec_revision_id OR OLD.command_id!=NEW.command_id
      OR OLD.admitted_version!=NEW.admitted_version OR OLD.check_config!=NEW.check_config
      OR OLD.config_hash!=NEW.config_hash OR (OLD.intent!='{}' AND OLD.intent!=NEW.intent)
      OR (OLD.integration_intent!='{}' AND OLD.integration_intent!=NEW.integration_intent)
      OR (OLD.integration_command_id IS NOT NULL AND OLD.integration_command_id IS NOT NEW.integration_command_id)
      OR OLD.status IN ('done','blocked','needs_input','failed','cancelled','interrupted')
    BEGIN SELECT RAISE(ABORT, 'delivery history is immutable'); END
    """)

    execute("""
    CREATE TRIGGER delivery_step_immutable BEFORE UPDATE ON delivery_steps
    WHEN OLD.id!=NEW.id OR OLD.delivery_id!=NEW.delivery_id OR OLD.number!=NEW.number
      OR OLD.kind!=NEW.kind OR OLD.cycle!=NEW.cycle OR OLD.input!=NEW.input
      OR OLD.status!='running'
    BEGIN SELECT RAISE(ABORT, 'delivery step is immutable'); END
    """)

    for table <- ["deliveries", "delivery_steps"] do
      execute(
        "CREATE TRIGGER #{table}_no_delete BEFORE DELETE ON #{table} BEGIN SELECT RAISE(ABORT, 'delivery history is immutable'); END"
      )
    end

    for operation <- ["INSERT", "UPDATE"] do
      execute("""
      CREATE TRIGGER delivery_guard_#{String.downcase(operation)} BEFORE #{operation} ON deliveries
      WHEN (NEW.status IN ('planning','implementing','testing','reviewing','integrating') OR NEW.cleanup='unknown')
        AND EXISTS (SELECT 1 FROM agent_runs WHERE status IN ('preparing','launching','running','stopping') OR cleanup='unknown')
      BEGIN SELECT RAISE(ABORT, 'another run owns execution'); END
      """)

      execute("""
      CREATE TRIGGER delivery_step_receipt_#{String.downcase(operation)} BEFORE #{operation} ON delivery_steps
      WHEN NEW.cycle NOT BETWEEN 0 AND 3 OR NEW.number NOT BETWEEN 1 AND 20
        OR NEW.kind NOT IN ('plan','implement','snapshot','check','review','publish','post_check')
        OR NEW.status NOT IN ('running','finished','failed','cancelled','interrupted')
        OR (NEW.status!='running' AND (json_extract(NEW.receipt,'$.status') IS NOT NEW.status
          OR COALESCE(json_extract(NEW.receipt,'$.cleanup'),'') NOT IN ('group_empty','not_started','unknown')))
      BEGIN SELECT RAISE(ABORT, 'invalid delivery step receipt'); END
      """)
    end

    execute("""
    CREATE TRIGGER agent_runs_delivery_guard BEFORE INSERT ON agent_runs
    WHEN EXISTS (SELECT 1 FROM deliveries WHERE #{active})
    BEGIN SELECT RAISE(ABORT, 'delivery owns execution'); END
    """)

    execute("""
    CREATE TRIGGER delivery_ready_evidence BEFORE UPDATE ON deliveries
    WHEN NEW.status='ready_to_merge' AND (NEW.cleanup!='group_empty' OR NOT EXISTS (
      SELECT 1 FROM delivery_steps r JOIN delivery_steps c ON c.id=json_extract(r.input,'$.check_step_id')
      JOIN delivery_steps p ON p.id=json_extract(r.input,'$.plan_step_id')
      WHERE r.delivery_id=NEW.id AND c.delivery_id=NEW.id AND p.delivery_id=NEW.id
        AND r.kind='review' AND c.kind='check' AND p.kind='plan'
        AND r.status='finished' AND c.status='finished' AND p.status='finished'
        AND r.cycle=NEW.cycle AND c.cycle=NEW.cycle
        AND json_extract(r.receipt,'$.report.verdict')='approved'
        AND json_extract(r.input,'$.candidate_commit')=json_extract(c.input,'$.candidate_commit')
        AND json_extract(c.input,'$.config_hash')=NEW.config_hash
        AND r.number=(SELECT MAX(number) FROM delivery_steps WHERE delivery_id=NEW.id)))
    BEGIN SELECT RAISE(ABORT, 'ready requires current checked review'); END
    """)

    execute("""
    CREATE TRIGGER delivery_done_evidence BEFORE UPDATE ON deliveries
    WHEN NEW.status='done' AND (OLD.status!='integrating' OR NEW.cleanup!='group_empty'
      OR NEW.integration_command_id IS NULL OR NOT EXISTS (
      SELECT 1 FROM delivery_steps c JOIN delivery_steps p ON p.id=json_extract(c.input,'$.publish_step_id')
      WHERE c.delivery_id=NEW.id AND p.delivery_id=NEW.id
        AND c.kind='post_check' AND p.kind='publish' AND c.status='finished' AND p.status='finished'
        AND c.cycle=NEW.cycle AND p.cycle=NEW.cycle
        AND json_extract(c.input,'$.config_hash')=NEW.config_hash
        AND json_extract(c.receipt,'$.candidate_commit')=json_extract(NEW.integration_intent,'$.candidate_commit')
        AND json_extract(p.receipt,'$.candidate_commit')=json_extract(NEW.integration_intent,'$.candidate_commit')
        AND c.number=(SELECT MAX(number) FROM delivery_steps WHERE delivery_id=NEW.id)))
    BEGIN SELECT RAISE(ABORT, 'done requires published checked commit'); END
    """)
  end

  def down do
    if repo().aggregate("deliveries", :count) > 0,
      do: raise("Refusing to discard delivery history")

    execute("DROP TRIGGER agent_runs_delivery_guard")
    drop table(:delivery_steps)
    drop table(:deliveries)
  end
end
