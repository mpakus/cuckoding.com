defmodule Boss.Repo.Migrations.AddExecutionRecovery do
  use Ecto.Migration

  def up do
    Boss.Repo.Migrations.AddExecutionRecoverySchema.up()
    flush()
    rewrite(true)
    execute(source_view())

    execute("""
    CREATE TRIGGER execution_retry_immutable BEFORE UPDATE ON deliveries
    WHEN NEW.execution_recovery_version IS NOT OLD.execution_recovery_version OR NEW.retry_implementation_id IS NOT OLD.retry_implementation_id
    BEGIN SELECT RAISE(ABORT, 'execution recovery source and policy are immutable'); END
    """)

    execute("""
    CREATE TRIGGER execution_retry_source BEFORE INSERT ON deliveries
    WHEN (NEW.execution_recovery_version=0 AND NEW.retry_implementation_id IS NOT NULL)
      OR (NEW.execution_recovery_version=1 AND (NEW.retry_review_id IS NOT NULL OR NEW.retry_candidate_commit IS NOT NULL
        OR NOT EXISTS (SELECT 1 FROM execution_retry_sources src JOIN deliveries p ON p.id=src.parent_id
          WHERE src.implementation_id=NEW.retry_implementation_id
            AND NEW.project_id=p.project_id AND NEW.task_id=p.task_id AND NEW.spec_revision_id=p.spec_revision_id
            AND NEW.admitted_version=src.terminal_version AND NEW.check_config=p.check_config AND NEW.config_hash=p.config_hash
            AND NEW.reviewer=p.reviewer AND NEW.autonomy_version=p.autonomy_version AND NEW.routing_version=p.routing_version
            AND NEW.model_catalog=p.model_catalog)))
      OR EXISTS (SELECT 1 FROM delivery_steps s JOIN deliveries p ON p.id=s.delivery_id
        WHERE s.id=NEW.retry_review_id AND p.execution_recovery_version=1)
    BEGIN SELECT RAISE(ABORT, 'execution retry requires its immutable terminal timeout source'); END
    """)

    execute("""
    CREATE TRIGGER execution_retry_base BEFORE UPDATE OF intent ON deliveries
    WHEN NEW.execution_recovery_version=1 AND NEW.intent!='{}' AND NOT EXISTS (
      SELECT 1 FROM delivery_steps s JOIN deliveries p ON p.id=s.delivery_id WHERE s.id=NEW.retry_implementation_id
        AND json_extract(NEW.intent,'$.base_commit')=json_extract(p.intent,'$.base_commit')
        AND json_extract(NEW.intent,'$.repo_path')=json_extract(p.intent,'$.repo_path')
        AND json_extract(NEW.intent,'$.git_common_dir')=json_extract(p.intent,'$.git_common_dir')
        AND json_extract(NEW.intent,'$.base_branch')=json_extract(p.intent,'$.base_branch'))
    BEGIN SELECT RAISE(ABORT, 'execution retry must preserve the original base'); END
    """)

    execute("""
    CREATE TRIGGER execution_seed_plan BEFORE INSERT ON delivery_steps
    WHEN NEW.kind='plan' AND EXISTS (SELECT 1 FROM deliveries WHERE id=NEW.delivery_id AND execution_recovery_version=1)
      AND NOT EXISTS (SELECT 1 FROM deliveries d JOIN execution_retry_sources src ON src.implementation_id=d.retry_implementation_id
        WHERE d.id=NEW.delivery_id AND NEW.number=1 AND NEW.cycle=0
          AND json_extract(NEW.input,'$.source_implementation_id')=src.implementation_id
          AND json_extract(NEW.input,'$.source_plan_id')=src.plan_id AND json_extract(NEW.input,'$.workspace')=d.intent
          AND COALESCE(json_type(NEW.input,'$.model_profile'),'null')='null')
    BEGIN SELECT RAISE(ABORT, 'retained plan requires its exact timeout source'); END
    """)

    execute("""
    CREATE TRIGGER execution_seed_receipt BEFORE UPDATE ON delivery_steps
    WHEN NEW.kind='plan' AND NEW.status='finished' AND
      (json_extract(NEW.receipt,'$.outcome')='retained_plan' OR EXISTS (
        SELECT 1 FROM deliveries WHERE id=NEW.delivery_id AND execution_recovery_version=1))
      AND NOT EXISTS (SELECT 1 FROM deliveries d JOIN execution_retry_sources src ON src.implementation_id=d.retry_implementation_id
        JOIN delivery_steps p ON p.id=src.plan_id WHERE d.id=NEW.delivery_id AND d.execution_recovery_version=1
          AND NEW.number=1 AND NEW.cycle=0 AND json_extract(NEW.input,'$.source_plan_id')=p.id
          AND json_extract(NEW.input,'$.source_implementation_id')=src.implementation_id
          AND json_extract(NEW.receipt,'$.outcome')='retained_plan' AND json_extract(NEW.receipt,'$.cleanup')='group_empty'
          AND (SELECT count(*) FROM json_each(NEW.receipt))=5
          AND (SELECT count(DISTINCT key) FROM json_each(NEW.receipt))=5
          AND NOT EXISTS (SELECT 1 FROM json_each(NEW.receipt) WHERE key NOT IN ('status','cleanup','outcome','report','workspace'))
          AND json_extract(NEW.receipt,'$.workspace')=d.intent
          AND NOT EXISTS (SELECT fullkey,type,atom FROM json_tree(NEW.receipt,'$.report') EXCEPT SELECT fullkey,type,atom FROM json_tree(p.receipt,'$.report'))
          AND NOT EXISTS (SELECT fullkey,type,atom FROM json_tree(p.receipt,'$.report') EXCEPT SELECT fullkey,type,atom FROM json_tree(NEW.receipt,'$.report')))
    BEGIN SELECT RAISE(ABORT, 'retained plan receipt cannot fabricate process evidence or change its source'); END
    """)

    execute("""
    CREATE TRIGGER execution_step_owner BEFORE INSERT ON delivery_steps
    WHEN EXISTS (SELECT 1 FROM deliveries WHERE id=NEW.delivery_id AND execution_recovery_version=1)
      AND NOT EXISTS (SELECT 1 FROM deliveries d JOIN tasks t ON t.id=d.task_id
        WHERE d.id=NEW.delivery_id AND d.status IN ('planning','implementing','testing','reviewing','integrating')
          AND d.cleanup!='unknown' AND t.state_version=d.task_version AND t.spec_revision_id=d.spec_revision_id
          AND NEW.number=(SELECT COALESCE(max(number),0)+1 FROM delivery_steps WHERE delivery_id=d.id))
    BEGIN SELECT RAISE(ABORT, 'execution recovery stage requires current owned delivery'); END
    """)

    execute(stage_guard())

    execute("""
    CREATE TRIGGER execution_timeout_receipt BEFORE UPDATE ON delivery_steps
    WHEN NEW.kind IN ('timeout_snapshot','timeout_check') AND NEW.status='finished' AND NOT COALESCE(
      (NEW.kind='timeout_snapshot' AND json_extract(NEW.receipt,'$.cleanup')='group_empty' AND json_extract(NEW.receipt,'$.workspace')=json_extract(NEW.input,'$.workspace')
        AND #{sha("json_extract(NEW.receipt,'$.candidate_commit')")}) OR
      (NEW.kind='timeout_check' AND #{passed("NEW")}
        AND json_extract(NEW.receipt,'$.candidate_commit')=json_extract(NEW.input,'$.candidate_commit')
        AND json_type(NEW.receipt,'$.output_complete')='true' AND #{hash("json_extract(NEW.receipt,'$.output_hash')")}),0)
    BEGIN SELECT RAISE(ABORT, 'timeout candidate receipt must bind exact fresh snapshot and checks'); END
    """)

    execute("""
    CREATE TRIGGER execution_retry_prefix BEFORE INSERT ON delivery_steps
    WHEN NEW.kind='implement' AND NEW.cycle=1 AND EXISTS (
      SELECT 1 FROM deliveries WHERE id=NEW.delivery_id AND execution_recovery_version=1)
      AND NOT EXISTS (SELECT 1 FROM delivery_steps r JOIN delivery_steps c ON c.id=json_extract(r.input,'$.source_step_id')
        WHERE r.delivery_id=NEW.delivery_id AND c.delivery_id=NEW.delivery_id AND c.kind='timeout_check' AND c.cycle=0
          AND r.number=NEW.number-1 AND r.kind='resolve' AND r.status='finished' AND #{passed("r")}
          AND json_type(r.receipt,'$.report.external_action')='null' AND #{checked("c")}
          AND json_extract(NEW.input,'$.parent_step_id')=r.id AND json_extract(NEW.input,'$.resolution_step_id')=r.id
          AND json_extract(NEW.input,'$.source_step_id')=c.id AND json_extract(NEW.input,'$.plan_step_id')=json_extract(c.input,'$.plan_step_id')
          AND json_extract(NEW.input,'$.workspace.base_commit')=json_extract(c.input,'$.candidate_commit'))
    BEGIN SELECT RAISE(ABORT, 'execution recovery requires fresh checks and alternate-model resolution'); END
    """)
  end

  def down do
    unless repo().query!("SELECT count(*) FROM deliveries WHERE execution_recovery_version=1").rows ==
             [[0]],
           do: raise("Refusing to discard execution recovery history")

    for name <-
          ~w(execution_retry_immutable execution_retry_source execution_retry_base execution_seed_plan execution_seed_receipt execution_step_owner execution_timeout_stage execution_timeout_receipt execution_retry_prefix),
        do: execute("DROP TRIGGER #{name}")

    execute("DROP VIEW execution_retry_sources")
    rewrite(false)
    Boss.Repo.Migrations.AddExecutionRecoverySchema.down()
  end

  defp source_view,
    do: """
    CREATE VIEW execution_retry_sources AS
    SELECT d.id AS parent_id,s.id AS implementation_id,p.id AS plan_id,e.version AS terminal_version
    FROM deliveries d JOIN delivery_steps s ON s.delivery_id=d.id
    JOIN delivery_steps p ON p.id=json_extract(s.input,'$.plan_step_id') AND p.delivery_id=d.id
    JOIN delivery_steps previous ON previous.id=json_extract(s.input,'$.parent_step_id') AND previous.delivery_id=d.id AND previous.number=s.number-1
    JOIN projects project ON project.id=d.project_id
    JOIN task_events e ON e.task_id=d.task_id AND e.command_id=d.id||':complete:failed'
    WHERE d.status='failed' AND d.cleanup='group_empty' AND d.autonomy_version=1 AND d.routing_version=2
      AND d.integration_intent='{}' AND d.integration_command_id IS NULL
      AND s.number=(SELECT max(number) FROM delivery_steps WHERE delivery_id=d.id) AND s.cycle=d.cycle AND #{timeout("s")}
      AND p.kind='plan' AND p.status='finished' AND (#{passed("p")} OR (d.execution_recovery_version=1 AND p.number=1 AND json_extract(p.receipt,'$.outcome')='retained_plan'))
      AND json_type(p.receipt,'$.report.acceptance')='array' AND json_array_length(p.receipt,'$.report.acceptance')>0
      AND COALESCE(json_type(p.receipt,'$.report.clarification'),'null')='null'
      AND e.action='delivery_progress' AND e.to_state='failed' AND e.version=d.task_version+1 AND e.spec_revision_id=d.spec_revision_id
      AND json_extract(s.input,'$.config_hash')=d.config_hash AND json_extract(p.input,'$.config_hash')=d.config_hash
      AND json_extract(s.input,'$.spec_revision_id')=d.spec_revision_id AND json_extract(p.input,'$.spec_revision_id')=d.spec_revision_id
      AND json_extract(d.intent,'$.project_id')=CAST(d.project_id AS TEXT) AND json_extract(d.intent,'$.repo_path')=project.root_path
      AND json_extract(d.intent,'$.git_common_dir')=project.git_common_dir AND json_extract(d.intent,'$.base_branch')=project.base_branch
      AND json_extract(s.input,'$.workspace.repo_path')=project.root_path AND json_extract(s.input,'$.workspace.git_common_dir')=project.git_common_dir
      AND json_extract(s.input,'$.workspace.base_branch')=project.base_branch AND json_extract(s.input,'$.workspace.project_id')=CAST(d.project_id AS TEXT)
      AND (SELECT count(*) FROM json_each(s.input,'$.workspace'))=8
      AND json_type(s.input,'$.model_profile.model')='text'
      AND ((s.cycle=1 AND d.retry_review_id IS NULL AND d.retry_implementation_id IS NULL AND previous.id=p.id
        AND json_extract(s.input,'$.workspace.base_commit')=json_extract(d.intent,'$.base_commit'))
      OR (s.cycle=1 AND d.retry_review_id IS NOT NULL AND previous.kind='retry_check'
        AND json_extract(s.input,'$.workspace.base_commit')=json_extract(previous.input,'$.candidate_commit') AND #{checked("previous")})
      OR (previous.kind='resolve' AND previous.cycle=s.cycle-1 AND previous.status='finished' AND #{passed("previous")}
        AND json_type(previous.receipt,'$.report.external_action')='null'
        AND json_extract(s.input,'$.workspace.base_commit')=json_extract(previous.input,'$.candidate_commit')))
    """

  defp stage_guard,
    do: """
    CREATE TRIGGER execution_timeout_stage BEFORE INSERT ON delivery_steps
    WHEN NEW.kind IN ('timeout_snapshot','timeout_check') AND NOT EXISTS (
      SELECT 1 FROM deliveries d JOIN delivery_steps previous ON previous.delivery_id=d.id AND previous.number=NEW.number-1
      JOIN delivery_steps p ON p.id=json_extract(NEW.input,'$.plan_step_id') AND p.delivery_id=d.id AND p.kind='plan' AND p.status='finished'
      JOIN delivery_steps s ON s.id=json_extract(NEW.input,'$.implementation_step_id')
      WHERE d.id=NEW.delivery_id AND d.execution_recovery_version=1 AND NEW.cycle BETWEEN 0 AND 4 AND #{timeout("s")}
        AND json_extract(NEW.input,'$.config_hash')=d.config_hash AND json_extract(NEW.input,'$.spec_revision_id')=d.spec_revision_id
        AND ((NEW.kind='timeout_snapshot'
          AND ((NEW.cycle=0 AND previous.id=p.id AND p.number=1 AND s.id=d.retry_implementation_id)
            OR (NEW.cycle>0 AND previous.id=s.id AND s.delivery_id=d.id AND s.cycle=NEW.cycle AND json_extract(s.input,'$.plan_step_id')=p.id))
          AND json_type(NEW.input,'$.workspace')='object' AND (SELECT count(*) FROM json_each(NEW.input,'$.workspace'))=4
          AND length(json_extract(NEW.input,'$.workspace.check_id'))=36
          AND json_extract(NEW.input,'$.workspace.ref')='refs/boss/checks/'||json_extract(NEW.input,'$.workspace.check_id')
          AND json_extract(NEW.input,'$.workspace.run_workspace')=json_extract(s.input,'$.workspace')
          AND json_type(NEW.input,'$.workspace.path')='text' AND json_extract(NEW.input,'$.workspace.path')!=json_extract(s.input,'$.workspace.path'))
        OR (NEW.kind='timeout_check' AND previous.kind='timeout_snapshot' AND previous.status='finished' AND previous.cycle=NEW.cycle
          AND json_extract(NEW.input,'$.snapshot_step_id')=previous.id
          AND json_extract(NEW.input,'$.implementation_step_id')=json_extract(previous.input,'$.implementation_step_id')
          AND json_extract(NEW.input,'$.plan_step_id')=json_extract(previous.input,'$.plan_step_id')
          AND json_extract(NEW.input,'$.workspace')=json_extract(previous.receipt,'$.workspace')
          AND json_extract(NEW.input,'$.candidate_commit')=json_extract(previous.receipt,'$.candidate_commit'))))
    BEGIN SELECT RAISE(ABORT, 'timeout snapshot and check require saved source lineage'); END
    """

  defp rewrite(up?) do
    timeout_source =
      "(SELECT json_extract(s.input,'$.model_profile.model') FROM delivery_steps problem LEFT JOIN delivery_steps chk ON chk.id=CASE WHEN problem.kind='review' THEN json_extract(problem.input,'$.check_step_id') ELSE problem.id END LEFT JOIN delivery_steps snap ON snap.id=json_extract(chk.input,'$.snapshot_step_id') JOIN delivery_steps s ON s.id=CASE WHEN problem.kind='implement' THEN problem.id WHEN problem.kind='timeout_check' THEN json_extract(problem.input,'$.implementation_step_id') ELSE json_extract(snap.input,'$.implementation_step_id') END WHERE problem.id=json_extract(NEW.input,'$.source_step_id') AND problem.delivery_id=d.id AND s.kind='implement')"

    preferred =
      "d.execution_recovery_version=1 AND NEW.kind IN ('resolve','implement') AND #{timeout_source} IS NOT NULL AND NOT (NEW.kind='resolve' AND json_extract(NEW.input,'$.resolution_attempt')=2)"

    old = "CASE WHEN NEW.kind='plan' AND EXISTS"

    old_plan =
      "json_extract(p.receipt,'$.cleanup')='group_empty' AND json_extract(p.receipt,'$.exit_kind')='exit' AND json_extract(p.receipt,'$.exit_code')=0 AND json_extract(p.receipt,'$.eof.stdout')=1 AND json_extract(p.receipt,'$.eof.stderr')=1"

    retained_plan =
      "(#{old_plan} OR (d.execution_recovery_version=1 AND p.number=1 AND p.cycle=0 AND json_extract(p.receipt,'$.outcome')='retained_plan' AND json_extract(p.receipt,'$.cleanup')='group_empty' AND EXISTS (SELECT 1 FROM execution_retry_sources src WHERE src.implementation_id=d.retry_implementation_id AND src.plan_id=json_extract(p.input,'$.source_plan_id') AND src.implementation_id=json_extract(p.input,'$.source_implementation_id'))))"

    changes =
      [
        {"delivery_publication_evidence", old_plan, retained_plan},
        {"merge_input", old_plan, retained_plan},
        {"deliveries_catalog_insert", "NEW.retry_review_id IS NULL",
         "NEW.retry_review_id IS NULL AND NEW.retry_implementation_id IS NULL"},
        {"delivery_catalog_model", "d.routing_version=2",
         "d.routing_version=2 AND NOT (d.execution_recovery_version=1 AND NEW.kind='plan' AND NEW.number=1)"},
        {"delivery_catalog_model", old,
         "CASE WHEN #{preferred} THEN CASE WHEN #{timeout_source}=json_extract(d.model_catalog,'$.resolver.model') THEN json_extract(d.model_catalog,'$.fallbacks[0]') ELSE json_extract(d.model_catalog,'$.resolver') END WHEN NEW.kind='plan' AND EXISTS"},
        {"delivery_catalog_model", "ORDER BY priority LIMIT 1",
         "AND NOT (#{preferred} AND json_extract(routes.profile,'$.model')=#{timeout_source}) ORDER BY priority LIMIT 1"},
        {"delivery_resolution_lineage", "OR (source.kind='check' AND",
         "OR (d.execution_recovery_version=1 AND source.kind='timeout_check' AND #{checked("source")}) OR (source.kind='check' AND"},
        {"delivery_resolution_lineage", "source.kind IN ('check','review')",
         "source.kind IN ('check','review','timeout_check')"},
        {"delivery_resolution_lineage", "source.cycle>1 AND",
         "(source.cycle>1 OR (d.execution_recovery_version=1 AND source.cycle=1)) AND"},
        {"delivery_resolution_continuation", "p.cycle>0 AND",
         "(p.cycle>0 OR (d.execution_recovery_version=1 AND p.cycle=0 AND EXISTS (SELECT 1 FROM delivery_steps tc WHERE tc.id=json_extract(p.input,'$.source_step_id') AND tc.kind='timeout_check' AND tc.delivery_id=d.id))) AND"}
      ] ++
        for name <- ~w(delivery_step_receipt_insert delivery_step_receipt_update),
            do:
              {name, "'retry_snapshot','retry_check','resolve'",
               "'retry_snapshot','retry_check','resolve','timeout_snapshot','timeout_check'"}

    for {name, old, new} <- if(up?, do: changes, else: Enum.reverse(changes)) do
      flush()

      type = if name == "delivery_publication_evidence", do: "view", else: "trigger"

      [[sql]] =
        repo().query!("SELECT sql FROM sqlite_master WHERE type=? AND name=?", [type, name]).rows

      {from, to} = if up?, do: {old, new}, else: {new, old}

      unless String.contains?(sql, from),
        do: raise("Unexpected #{name} execution recovery boundary")

      execute("DROP #{String.upcase(type)} #{name}")
      execute(String.replace(sql, from, to))
    end

    flush()
  end

  defp timeout(s),
    do:
      "#{s}.kind='implement' AND #{s}.status='failed' AND json_extract(#{s}.receipt,'$.outcome')='timeout' AND json_extract(#{s}.receipt,'$.cleanup')='group_empty' AND json_type(#{s}.receipt,'$.eof.stdout')='true' AND json_type(#{s}.receipt,'$.eof.stderr')='true' AND ((json_extract(#{s}.receipt,'$.exit_kind')='exit' AND json_type(#{s}.receipt,'$.exit_code')='integer' AND json_extract(#{s}.receipt,'$.exit_code') BETWEEN 0 AND 2147483647 AND json_type(#{s}.receipt,'$.signal')='null') OR (json_extract(#{s}.receipt,'$.exit_kind')='signal' AND json_type(#{s}.receipt,'$.signal')='integer' AND json_extract(#{s}.receipt,'$.signal') BETWEEN 1 AND 128 AND json_type(#{s}.receipt,'$.exit_code')='null'))"

  defp transport(s),
    do:
      "json_extract(#{s}.receipt,'$.cleanup')='group_empty' AND json_extract(#{s}.receipt,'$.exit_kind')='exit' AND json_type(#{s}.receipt,'$.exit_code')='integer' AND json_type(#{s}.receipt,'$.eof.stdout')='true' AND json_type(#{s}.receipt,'$.eof.stderr')='true'"

  defp passed(s), do: "(#{transport(s)} AND json_extract(#{s}.receipt,'$.exit_code')=0)"

  defp checked(s),
    do:
      "(#{transport(s)} AND json_extract(#{s}.receipt,'$.candidate_commit')=json_extract(#{s}.input,'$.candidate_commit') AND json_type(#{s}.receipt,'$.output_complete')='true' AND #{hash("json_extract(#{s}.receipt,'$.output_hash')")} AND ((#{s}.status='finished' AND json_extract(#{s}.receipt,'$.exit_code')=0) OR (#{s}.status='failed' AND json_extract(#{s}.receipt,'$.outcome')='checks_failed' AND json_type(#{s}.receipt,'$.exit_code')='integer' AND json_extract(#{s}.receipt,'$.exit_code')!=0)))"

  defp hash(s), do: "(length(#{s})=64 AND #{s} NOT GLOB '*[^0-9a-f]*')"
  defp sha(s), do: "(length(#{s}) IN (40,64) AND #{s} NOT GLOB '*[^0-9a-f]*')"
end

defmodule Boss.Repo.Migrations.AddExecutionRecoverySchema do
  use Ecto.Migration

  def up do
    execute(
      "ALTER TABLE deliveries ADD COLUMN execution_recovery_version INTEGER NOT NULL DEFAULT 0 CHECK (execution_recovery_version IN (0,1))"
    )

    execute(
      "ALTER TABLE deliveries ADD COLUMN retry_implementation_id TEXT REFERENCES delivery_steps(id) ON DELETE RESTRICT"
    )
  end

  def down do
    unless repo().query!(
             "SELECT count(*) FROM deliveries WHERE execution_recovery_version=1 OR retry_implementation_id IS NOT NULL"
           ).rows == [[0]], do: raise("Refusing to discard execution recovery history")

    execute("ALTER TABLE deliveries DROP COLUMN retry_implementation_id")
    execute("ALTER TABLE deliveries DROP COLUMN execution_recovery_version")
  end
end
