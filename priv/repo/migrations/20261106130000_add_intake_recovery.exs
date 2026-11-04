defmodule Boss.Repo.Migrations.AddIntakeRecovery do
  use Ecto.Migration

  @validation ~w(valid report_empty report_too_large report_unavailable report_replaced invalid_encoding invalid_json invalid_shape duplicate_keys unknown_fields task_limit invalid_task_id invalid_title invalid_specification invalid_acceptance invalid_dependencies invalid_sources duplicate_task_id dependency_cycle)
  @keys ~w(status cleanup outcome exit_kind exit_code signal eof usage error_class report_bytes validation_code plan_hash)
  @outcomes ~w(exited invalid_report cancelled interrupted failed timeout timed_out output_limit unsupported codex_unavailable candidate_changed target_changed cleanup_unknown)
  @errors ~w(model_unavailable auth rate_limit schema transport unknown)

  def up do
    Boss.Repo.Migrations.AddIntakeRecoverySchema.up()
    flush()

    execute("""
    CREATE TRIGGER intake_planning_version_immutable BEFORE UPDATE ON project_intakes
    WHEN NEW.planning_version IS NOT OLD.planning_version
      OR (NEW.planning_version=0 AND NEW.accepted_attempt_id IS NOT NULL)
      OR (OLD.accepted_attempt_id IS NOT NULL AND NEW.accepted_attempt_id IS NOT OLD.accepted_attempt_id)
    BEGIN SELECT RAISE(ABORT, 'intake planning policy and acceptance are immutable'); END
    """)

    execute("""
    CREATE TRIGGER intake_planning_initial BEFORE INSERT ON project_intakes
    WHEN NEW.accepted_attempt_id IS NOT NULL OR (NEW.planning_version=1 AND
      (NEW.routing_version!=2 OR NEW.autonomy_version!=1 OR NEW.status!='planning'
        OR NEW.cleanup!='pending' OR NEW.workspace!='{}' OR NEW.model_catalog!='{}'))
    BEGIN SELECT RAISE(ABORT, 'intake recovery begins with pinned current routing'); END
    """)

    execute("""
    CREATE TRIGGER intake_attempt_insert BEFORE INSERT ON project_intake_attempts
    WHEN NEW.status!='running' OR NEW.receipt!='{}' OR length(NEW.id)!=36 OR
      NOT COALESCE((SELECT r.planning_version=1 AND r.routing_version=2 AND r.status='planning'
        AND r.stop_requested=0 AND r.cleanup='pending' AND r.model_catalog!='{}'
        AND NEW.source_base=json_extract(r.workspace,'$.base_commit')
        AND length(NEW.source_base) IN (40,64) AND NEW.source_base NOT GLOB '*[^0-9a-f]*'
        AND NEW.number BETWEEN 1 AND 3
        AND (SELECT count(DISTINCT json_extract(startup.model_profile,'$.model')) FROM project_intake_attempts startup
          WHERE startup.request_id=r.id AND startup.status='failed' AND #{transport("startup.receipt")}
            AND json_extract(startup.receipt,'$.outcome')='exited'
            AND COALESCE(json_extract(startup.receipt,'$.error_class'),'') IN ('','unknown')
            AND (json_extract(startup.receipt,'$.exit_code')!=0 OR json_extract(startup.receipt,'$.error_class')='unknown'))<2
        AND NEW.number=(SELECT count(*)+1 FROM project_intake_attempts WHERE request_id=r.id)
        AND ((NEW.number=1 AND NEW.previous_attempt_id IS NULL) OR
          EXISTS (SELECT 1 FROM project_intake_attempts p WHERE p.id=NEW.previous_attempt_id
            AND p.request_id=r.id AND p.number=NEW.number-1 AND #{recoverable("p")}))
        AND #{profile("NEW.model_profile")}
        AND EXISTS (SELECT 1 FROM (
          SELECT json_extract(r.model_catalog,'$.primary') AS profile, -1 AS priority WHERE NEW.number=1
          UNION ALL
          SELECT f.value AS profile, CAST(f.key AS INTEGER) AS priority
          FROM json_each(r.model_catalog,'$.fallbacks') f WHERE NEW.number>1
            AND json_extract(f.value,'$.model')!=(SELECT json_extract(p.model_profile,'$.model')
              FROM project_intake_attempts p WHERE p.id=NEW.previous_attempt_id)
            AND NOT EXISTS (SELECT 1 FROM project_intake_attempts unavailable WHERE unavailable.request_id=r.id
              AND unavailable.status='failed' AND #{transport("unavailable.receipt")}
              AND json_extract(unavailable.receipt,'$.outcome')='exited'
              AND json_extract(unavailable.receipt,'$.error_class')='model_unavailable'
              AND json_extract(unavailable.model_profile,'$.model')=json_extract(f.value,'$.model'))
          ORDER BY priority LIMIT 1
        ) selected WHERE json_extract(NEW.model_profile,'$.model')=json_extract(selected.profile,'$.model')
          AND json_extract(NEW.model_profile,'$.reasoning_effort')=json_extract(selected.profile,'$.reasoning_effort'))
        FROM project_intakes r WHERE r.id=NEW.request_id),0)
    BEGIN SELECT RAISE(ABORT, 'intake attempt requires bounded saved lineage and alternate model'); END
    """)

    execute("""
    CREATE TRIGGER intake_attempt_update BEFORE UPDATE ON project_intake_attempts
    WHEN OLD.status!='running' OR NEW.id IS NOT OLD.id OR NEW.request_id IS NOT OLD.request_id
      OR NEW.number IS NOT OLD.number OR NEW.previous_attempt_id IS NOT OLD.previous_attempt_id
      OR NEW.source_base IS NOT OLD.source_base OR NEW.model_profile IS NOT OLD.model_profile
      OR NEW.inserted_at IS NOT OLD.inserted_at
      OR NOT EXISTS (SELECT 1 FROM project_intakes WHERE id=OLD.request_id AND status='planning')
      OR NOT COALESCE(#{receipt("NEW.receipt")},0)
      OR NEW.status!=json_extract(NEW.receipt,'$.status')
    BEGIN SELECT RAISE(ABORT, 'intake attempt receipt must be bounded and terminal'); END
    """)

    execute("""
    CREATE TRIGGER intake_attempt_delete BEFORE DELETE ON project_intake_attempts
    BEGIN SELECT RAISE(ABORT, 'intake attempt history is immutable'); END
    """)

    execute("""
    CREATE TRIGGER intake_attempt_terminal BEFORE UPDATE ON project_intakes
    WHEN NEW.planning_version=1 AND (
      (NEW.status!='planning' AND EXISTS (SELECT 1 FROM project_intake_attempts a WHERE a.request_id=OLD.id AND a.status='running'))
      OR (EXISTS (SELECT 1 FROM project_intake_attempts a WHERE a.request_id=OLD.id AND json_extract(a.receipt,'$.cleanup')='unknown')
        AND NEW.status!='planning' AND (NEW.status!='interrupted' OR NEW.cleanup!='unknown'))
      OR (NEW.accepted_attempt_id IS NOT NULL AND NEW.status!='finished')
      OR (NEW.status='finished' AND (NEW.stop_requested!=0 OR NEW.cleanup!='group_empty'
        OR NOT EXISTS (SELECT 1 FROM project_intake_attempts a WHERE a.id=NEW.accepted_attempt_id
          AND a.request_id=OLD.id AND a.status='finished' AND a.source_base=json_extract(OLD.workspace,'$.base_commit')
          AND a.number=(SELECT max(number) FROM project_intake_attempts WHERE request_id=OLD.id)))))
    BEGIN SELECT RAISE(ABORT, 'intake completion requires its latest verified attempt'); END
    """)

    execute("""
    CREATE TRIGGER intake_attempt_batch BEFORE INSERT ON autopilots
    WHEN EXISTS (SELECT 1 FROM project_intakes r WHERE r.project_id=NEW.project_id AND r.command_id=NEW.command_id
      AND r.planning_version=1 AND (r.status!='planning' OR r.stop_requested!=0
        OR NOT EXISTS (SELECT 1 FROM project_intake_attempts a WHERE a.request_id=r.id AND a.status='finished'
          AND a.source_base=json_extract(r.workspace,'$.base_commit')
          AND a.number=(SELECT max(number) FROM project_intake_attempts WHERE request_id=r.id))))
    BEGIN SELECT RAISE(ABORT, 'intake handoff requires its latest verified attempt'); END
    """)
  end

  def down do
    unless repo().query!("SELECT count(*) FROM project_intakes WHERE planning_version=1").rows ==
             [[0]],
           do: raise("Refusing to discard intake recovery policy or attempts")

    for name <- ~w(intake_planning_version_immutable intake_planning_initial intake_attempt_insert
      intake_attempt_update intake_attempt_delete intake_attempt_terminal intake_attempt_batch),
        do: execute("DROP TRIGGER #{name}")

    Boss.Repo.Migrations.AddIntakeRecoverySchema.down()
  end

  defp recoverable(a),
    do: """
    #{a}.status='failed' AND #{transport(a <> ".receipt")}
    AND COALESCE(json_extract(#{a}.receipt,'$.error_class'),'') NOT IN ('auth','rate_limit','schema','transport')
    AND ((json_extract(#{a}.receipt,'$.outcome')='invalid_report'
      AND json_extract(#{a}.receipt,'$.validation_code') IN (#{quoted(@validation -- ~w(valid report_unavailable report_replaced))}))
      OR (json_extract(#{a}.receipt,'$.outcome')='exited' AND (json_extract(#{a}.receipt,'$.exit_code')!=0
        OR json_extract(#{a}.receipt,'$.error_class') IN ('model_unavailable','unknown'))))
    """

  defp transport(r),
    do: """
    json_extract(#{r},'$.cleanup')='group_empty' AND json_extract(#{r},'$.exit_kind')='exit'
    AND json_type(#{r},'$.exit_code')='integer' AND json_type(#{r},'$.signal')='null'
    AND json_type(#{r},'$.eof.stdout')='true' AND json_type(#{r},'$.eof.stderr')='true'
    """

  defp profile(p),
    do: """
    json_valid(#{p}) AND json_type(#{p})='object'
    AND (SELECT count(*) FROM json_each(#{p}))=2 AND (SELECT count(DISTINCT key) FROM json_each(#{p}))=2
    AND NOT EXISTS (SELECT 1 FROM json_each(#{p}) WHERE key NOT IN ('model','reasoning_effort') OR type!='text')
    """

  defp receipt(r),
    do: """
    json_valid(#{r}) AND length(CAST(#{r} AS BLOB))<=8192 AND json_type(#{r})='object'
    AND (SELECT count(*) FROM json_each(#{r}))=12 AND (SELECT count(DISTINCT key) FROM json_each(#{r}))=12
    AND NOT EXISTS (SELECT 1 FROM json_each(#{r}) WHERE key NOT IN (#{quoted(@keys)}))
    AND json_extract(#{r},'$.status') IN ('finished','failed','cancelled','interrupted')
    AND json_extract(#{r},'$.cleanup') IN ('group_empty','unknown','not_started')
    AND json_extract(#{r},'$.outcome') IN (#{quoted(@outcomes)})
    AND (json_type(#{r},'$.exit_kind')='null' OR json_extract(#{r},'$.exit_kind') IN ('exit','signal'))
    AND #{nullable_int(r, "exit_code", 2_147_483_647)}
    AND (json_type(#{r},'$.signal')='null' OR (json_type(#{r},'$.signal')='integer' AND json_extract(#{r},'$.signal') BETWEEN 1 AND 128))
    AND json_type(#{r},'$.eof')='object' AND (SELECT count(*) FROM json_each(#{r},'$.eof'))=2
    AND (SELECT count(DISTINCT key) FROM json_each(#{r},'$.eof'))=2
    AND NOT EXISTS (SELECT 1 FROM json_each(#{r},'$.eof') WHERE key NOT IN ('stdout','stderr') OR type NOT IN ('true','false'))
    AND json_type(#{r},'$.usage')='object' AND (SELECT count(*) FROM json_each(#{r},'$.usage'))<=3
    AND (SELECT count(*) FROM json_each(#{r},'$.usage'))=(SELECT count(DISTINCT key) FROM json_each(#{r},'$.usage'))
    AND NOT EXISTS (SELECT 1 FROM json_each(#{r},'$.usage') WHERE key NOT IN ('input_tokens','cached_input_tokens','output_tokens')
      OR type!='integer' OR value NOT BETWEEN 0 AND 9007199254740991)
    AND (json_type(#{r},'$.error_class')='null' OR json_extract(#{r},'$.error_class') IN (#{quoted(@errors)}))
    AND #{nullable_int(r, "report_bytes", 9_007_199_254_740_991)}
    AND (json_type(#{r},'$.validation_code')='null' OR json_extract(#{r},'$.validation_code') IN (#{quoted(@validation)}))
    AND (json_type(#{r},'$.plan_hash')='null' OR #{hash(r)})
    AND ((json_extract(#{r},'$.status')='finished' AND #{transport(r)}
      AND json_extract(#{r},'$.outcome')='exited' AND json_extract(#{r},'$.exit_code')=0
      AND json_type(#{r},'$.error_class')='null' AND json_extract(#{r},'$.validation_code')='valid'
      AND #{hash(r)} AND json_type(#{r},'$.report_bytes')='integer' AND json_extract(#{r},'$.report_bytes') BETWEEN 1 AND 32768)
    OR (json_extract(#{r},'$.status')='interrupted' AND json_extract(#{r},'$.cleanup')='unknown' AND json_type(#{r},'$.plan_hash')='null')
    OR (json_extract(#{r},'$.status') IN ('failed','cancelled') AND json_extract(#{r},'$.cleanup') IN ('group_empty','not_started')
      AND json_type(#{r},'$.plan_hash')='null' AND COALESCE(json_extract(#{r},'$.validation_code'),'')!='valid'))
    """

  defp nullable_int(r, key, max),
    do:
      "(json_type(#{r},'$.#{key}')='null' OR (json_type(#{r},'$.#{key}')='integer' AND json_extract(#{r},'$.#{key}') BETWEEN 0 AND #{max}))"

  defp hash(r),
    do:
      "(json_type(#{r},'$.plan_hash')='text' AND length(json_extract(#{r},'$.plan_hash'))=64 AND json_extract(#{r},'$.plan_hash') NOT GLOB '*[^0-9a-f]*')"

  defp quoted(values), do: Enum.map_join(values, ",", &("'" <> &1 <> "'"))
end

defmodule Boss.Repo.Migrations.AddIntakeRecoverySchema do
  use Ecto.Migration

  def up do
    execute(
      "ALTER TABLE project_intakes ADD COLUMN planning_version INTEGER NOT NULL DEFAULT 0 CHECK (planning_version IN (0,1))"
    )

    create table(:project_intake_attempts, primary_key: false) do
      add :id, :text, primary_key: true

      add :request_id, references(:project_intakes, type: :text, on_delete: :restrict),
        null: false

      add :number, :integer, null: false

      add :previous_attempt_id,
          references(:project_intake_attempts, type: :text, on_delete: :restrict)

      add :source_base, :text, null: false
      add :model_profile, :map, null: false
      add :status, :text, null: false, default: "running"
      add :receipt, :map, null: false, default: %{}
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:project_intake_attempts, [:request_id, :number])
    create unique_index(:project_intake_attempts, [:request_id], where: "status='running'")

    alter table(:project_intakes) do
      add :accepted_attempt_id,
          references(:project_intake_attempts, type: :text, on_delete: :restrict)
    end
  end

  def down do
    unless repo().query!("SELECT count(*) FROM project_intakes WHERE planning_version=1").rows ==
             [[0]] and
             repo().query!("SELECT count(*) FROM project_intake_attempts").rows == [[0]],
           do: raise("Refusing to discard intake recovery policy or attempts")

    execute("ALTER TABLE project_intakes DROP COLUMN accepted_attempt_id")
    drop table(:project_intake_attempts)
    execute("ALTER TABLE project_intakes DROP COLUMN planning_version")
  end
end
