defmodule Boss.Repo.Migrations.AddCheckpointRecovery do
  use Ecto.Migration

  @network_policy %{
    "version" => 1,
    "network_access" => true,
    "proxy" => true,
    "allow_local_binding" => true,
    "domains" => [
      "127.0.0.1",
      "builds.hex.pm",
      "github.com",
      "hex.pm",
      "localhost",
      "registry.npmjs.org",
      "release-assets.githubusercontent.com",
      "repo.hex.pm"
    ]
  }

  def up do
    Boss.Repo.Migrations.AddCheckpointRecoverySchema.up()
    flush()
    execute(source_view())

    execute("""
    CREATE VIEW retained_retry_sources AS
    SELECT d.id AS child_id, src.parent_id,src.implementation_id,src.plan_id,src.terminal_version
    FROM deliveries d JOIN execution_retry_sources src ON src.implementation_id=d.retry_implementation_id
    WHERE d.checkpoint_recovery_version=0
    UNION ALL
    SELECT d.id,src.parent_id,src.implementation_id,src.plan_id,src.terminal_version
    FROM deliveries d JOIN checkpoint_retry_sources src ON src.implementation_id=d.retry_implementation_id
      AND src.check_id IS d.retry_source_check_id WHERE d.checkpoint_recovery_version=1
    """)

    rewrite(true)

    execute("""
    CREATE TRIGGER checkpoint_policy_immutable BEFORE UPDATE ON deliveries
    WHEN NEW.checkpoint_recovery_version IS NOT OLD.checkpoint_recovery_version
      OR NEW.implementation_network_version IS NOT OLD.implementation_network_version
      OR NEW.retry_source_check_id IS NOT OLD.retry_source_check_id
    BEGIN SELECT RAISE(ABORT,'checkpoint source and network policy are immutable'); END
    """)

    execute("""
    CREATE TRIGGER checkpoint_source BEFORE INSERT ON deliveries
    WHEN (NEW.checkpoint_recovery_version=0 AND (NEW.retry_source_check_id IS NOT NULL OR NEW.implementation_network_version!=0))
      OR (NEW.checkpoint_recovery_version=1 AND (NEW.execution_recovery_version!=1 OR NEW.implementation_network_version!=1
        OR NEW.retry_review_id IS NOT NULL OR NEW.retry_candidate_commit IS NOT NULL
        OR NOT EXISTS (SELECT 1 FROM checkpoint_retry_sources src JOIN deliveries p ON p.id=src.parent_id
          WHERE src.implementation_id=NEW.retry_implementation_id AND src.check_id IS NEW.retry_source_check_id
            AND NEW.project_id=p.project_id AND NEW.task_id=p.task_id AND NEW.spec_revision_id=p.spec_revision_id
            AND NEW.admitted_version=src.terminal_version AND NEW.check_config=p.check_config AND NEW.config_hash=p.config_hash
            AND NEW.reviewer=p.reviewer AND NEW.autonomy_version=p.autonomy_version AND NEW.routing_version=p.routing_version
            AND NEW.model_catalog=p.model_catalog)))
    BEGIN SELECT RAISE(ABORT,'checkpoint recovery requires its exact terminal source'); END
    """)

    execute("""
    CREATE TRIGGER checkpoint_seed_plan BEFORE INSERT ON delivery_steps
    WHEN NEW.kind='plan' AND EXISTS(SELECT 1 FROM deliveries d WHERE d.id=NEW.delivery_id AND d.checkpoint_recovery_version=1
      AND json_extract(NEW.input,'$.source_check_id') IS NOT d.retry_source_check_id)
    BEGIN SELECT RAISE(ABORT,'retained checkpoint plan requires original check'); END
    """)

    execute(stage_guard())

    execute("""
    CREATE TRIGGER checkpoint_receipt BEFORE UPDATE ON delivery_steps
    WHEN NEW.kind IN ('checkpoint_snapshot','checkpoint_check') AND NEW.status='finished' AND NOT COALESCE(
      (NEW.kind='checkpoint_snapshot' AND json_extract(NEW.receipt,'$.cleanup')='group_empty'
        AND #{sha("json_extract(NEW.receipt,'$.candidate_commit')")}
        AND json_type(NEW.receipt,'$.workspace')='object' AND (SELECT count(*) FROM json_each(NEW.receipt,'$.workspace'))=4
        AND json_extract(NEW.receipt,'$.workspace.check_id')=json_extract(NEW.input,'$.check_id')
        AND json_extract(NEW.receipt,'$.workspace.run_workspace')=json_extract(NEW.input,'$.run_workspace')
        AND json_extract(NEW.receipt,'$.workspace.ref')='refs/boss/checks/'||json_extract(NEW.input,'$.check_id')
        AND json_type(NEW.receipt,'$.workspace.path')='text') OR
      (NEW.kind='checkpoint_check' AND #{passed("NEW")} AND #{complete_check("NEW")}),0)
    BEGIN SELECT RAISE(ABORT,'checkpoint receipt must bind fresh saved snapshot and checks'); END
    """)

    network = JSON.encode!(@network_policy) |> String.replace("'", "''")

    execute("""
    CREATE TRIGGER implementation_network_profile BEFORE INSERT ON delivery_steps
    WHEN NOT EXISTS (SELECT 1 FROM deliveries d WHERE d.id=NEW.delivery_id AND
      (((NEW.kind!='implement' OR d.implementation_network_version=0) AND COALESCE(json_type(NEW.input,'$.network_policy'),'null')='null')
      OR (NEW.kind='implement' AND d.implementation_network_version=1 AND json_type(NEW.input,'$.network_policy')='object'
        AND (SELECT count(*) FROM json_each(NEW.input,'$.network_policy'))=(SELECT count(*) FROM json_each('#{network}'))
        AND NOT EXISTS (SELECT fullkey,type,atom FROM json_tree(NEW.input,'$.network_policy') EXCEPT SELECT '$.network_policy'||substr(fullkey,2),type,atom FROM json_tree('#{network}'))
        AND NOT EXISTS (SELECT '$.network_policy'||substr(fullkey,2),type,atom FROM json_tree('#{network}') EXCEPT SELECT fullkey,type,atom FROM json_tree(NEW.input,'$.network_policy')))))
    BEGIN SELECT RAISE(ABORT,'implementation network policy must match saved version'); END
    """)
  end

  def down do
    unless repo().query!(
             "SELECT count(*) FROM deliveries WHERE checkpoint_recovery_version=1 OR implementation_network_version=1"
           ).rows == [[0]], do: raise("Refusing to discard checkpoint recovery history")

    for name <-
          ~w(checkpoint_policy_immutable checkpoint_source checkpoint_seed_plan checkpoint_stage checkpoint_receipt implementation_network_profile),
        do: execute("DROP TRIGGER #{name}")

    rewrite(false)
    execute("DROP VIEW retained_retry_sources")
    execute("DROP VIEW checkpoint_retry_sources")
    Boss.Repo.Migrations.AddCheckpointRecoverySchema.down()
  end

  defp source_view,
    do: """
    CREATE VIEW checkpoint_retry_sources AS
    SELECT parent_id,implementation_id,plan_id,terminal_version,NULL AS check_id FROM execution_retry_sources
    UNION ALL
    SELECT d.id,s.id,p.id,e.version,c.id
    FROM deliveries d
      JOIN delivery_steps last ON last.delivery_id=d.id AND last.number=(SELECT max(number) FROM delivery_steps WHERE delivery_id=d.id)
      JOIN delivery_steps c ON c.id=CASE WHEN last.kind='resolve' THEN json_extract(last.input,'$.source_step_id') ELSE last.id END AND c.delivery_id=d.id
      JOIN delivery_steps snap ON snap.id=json_extract(c.input,'$.snapshot_step_id') AND snap.delivery_id=d.id
      JOIN delivery_steps s ON s.id=json_extract(snap.input,'$.implementation_step_id')
      LEFT JOIN delivery_steps previous ON previous.id=json_extract(s.input,'$.parent_step_id') AND previous.delivery_id=s.delivery_id AND previous.number=s.number-1
      JOIN delivery_steps p ON p.id=json_extract(c.input,'$.plan_step_id') AND p.delivery_id=d.id
      JOIN projects project ON project.id=d.project_id
      JOIN task_events e ON e.task_id=d.task_id AND e.command_id=d.id||':complete:'||d.status
    WHERE d.status IN ('failed','blocked','needs_input') AND d.cleanup='group_empty' AND d.autonomy_version=1 AND d.routing_version=2
      AND d.integration_intent='{}' AND d.integration_command_id IS NULL
      AND COALESCE(d.failure_code,'') NOT IN ('provider_auth','provider_rate_limit','provider_schema','provider_transport')
      AND e.action='delivery_progress' AND e.to_state=d.status AND e.version=d.task_version+1 AND e.spec_revision_id=d.spec_revision_id
      AND c.kind IN ('check','timeout_check','checkpoint_check') AND c.status='failed' AND c.cycle=d.cycle
      AND ((#{transport("c")} AND json_extract(c.receipt,'$.exit_code')!=0 AND json_extract(c.receipt,'$.outcome')='checks_failed' AND #{complete_check("c")}) OR #{check_timeout("c")}) AND #{sha("json_extract(c.input,'$.candidate_commit')")}
      AND (last.id=c.id OR (last.kind='resolve' AND last.cycle=c.cycle AND #{transport("last")}
        AND json_extract(last.input,'$.plan_step_id')=p.id AND json_extract(last.input,'$.workspace')=json_extract(c.input,'$.workspace')
        AND json_extract(last.input,'$.candidate_commit')=json_extract(c.input,'$.candidate_commit')
        AND json_extract(last.receipt,'$.candidate_commit')=json_extract(c.input,'$.candidate_commit')
        AND COALESCE(json_extract(last.receipt,'$.summary.error_class'),'') NOT IN ('auth','rate_limit','schema','transport')
        AND ((last.status='finished' AND json_extract(last.receipt,'$.exit_code')=0 AND json_type(last.receipt,'$.report')='object')
          OR (last.status='failed' AND json_extract(last.receipt,'$.outcome') IN ('invalid_report','exited')))))
      AND snap.kind=CASE c.kind WHEN 'check' THEN 'snapshot' WHEN 'timeout_check' THEN 'timeout_snapshot' ELSE 'checkpoint_snapshot' END
      AND snap.status='finished' AND json_extract(snap.receipt,'$.cleanup')='group_empty' AND snap.cycle=c.cycle AND snap.number=c.number-1
      AND json_extract(snap.receipt,'$.candidate_commit')=json_extract(c.input,'$.candidate_commit')
      AND json_extract(snap.receipt,'$.workspace')=json_extract(c.input,'$.workspace') AND json_extract(snap.input,'$.plan_step_id')=p.id
      AND s.kind='implement' AND json_type(s.input,'$.model_profile.model')='text'
      AND ((c.kind='check' AND s.delivery_id=d.id AND s.cycle=c.cycle AND s.status='finished' AND #{passed("s")}
        AND json_extract(s.input,'$.plan_step_id')=p.id AND #{implementation_base()})
      OR (c.kind='timeout_check' AND #{timeout("s")} AND ((c.cycle=0 AND s.id=d.retry_implementation_id)
        OR (s.delivery_id=d.id AND s.cycle=c.cycle AND #{implementation_base()})))
      OR (c.kind='checkpoint_check' AND d.checkpoint_recovery_version=1 AND c.cycle=0 AND s.id=d.retry_implementation_id
        AND json_extract(c.input,'$.source_check_id')=d.retry_source_check_id))
      AND p.kind='plan' AND p.status='finished' AND (#{passed("p")} OR (d.execution_recovery_version=1 AND p.number=1 AND json_extract(p.receipt,'$.outcome')='retained_plan'))
      AND json_type(p.receipt,'$.report.acceptance')='array' AND json_array_length(p.receipt,'$.report.acceptance')>0
      AND COALESCE(json_type(p.receipt,'$.report.clarification'),'null')='null'
      AND json_extract(p.input,'$.config_hash')=d.config_hash AND json_extract(c.input,'$.config_hash')=d.config_hash AND json_extract(snap.input,'$.config_hash')=d.config_hash
      AND json_extract(p.input,'$.spec_revision_id')=d.spec_revision_id AND json_extract(c.input,'$.spec_revision_id')=d.spec_revision_id AND json_extract(snap.input,'$.spec_revision_id')=d.spec_revision_id
      AND json_extract(d.intent,'$.project_id')=CAST(d.project_id AS TEXT) AND json_extract(d.intent,'$.repo_path')=project.root_path
      AND json_extract(d.intent,'$.git_common_dir')=project.git_common_dir AND json_extract(d.intent,'$.base_branch')=project.base_branch
      AND #{sha("json_extract(d.intent,'$.base_commit')")}
      AND json_extract(s.input,'$.workspace.repo_path')=project.root_path AND json_extract(s.input,'$.workspace.git_common_dir')=project.git_common_dir
      AND json_extract(s.input,'$.workspace.base_branch')=project.base_branch AND json_extract(s.input,'$.workspace.project_id')=CAST(d.project_id AS TEXT)
      AND (SELECT count(*) FROM json_each(s.input,'$.workspace'))=8 AND #{sha("json_extract(s.input,'$.workspace.base_commit')")}
    """

  defp stage_guard,
    do: """
    CREATE TRIGGER checkpoint_stage BEFORE INSERT ON delivery_steps
    WHEN NEW.kind IN ('checkpoint_snapshot','checkpoint_check') AND NOT EXISTS (
      SELECT 1 FROM deliveries d JOIN checkpoint_retry_sources src ON src.implementation_id=d.retry_implementation_id AND src.check_id=d.retry_source_check_id
      JOIN delivery_steps c ON c.id=src.check_id
      JOIN delivery_steps p ON p.id=json_extract(NEW.input,'$.plan_step_id') AND p.delivery_id=d.id AND p.kind='plan' AND p.number=1 AND p.status='finished'
      JOIN delivery_steps previous ON previous.delivery_id=d.id AND previous.number=NEW.number-1
      WHERE d.id=NEW.delivery_id AND d.checkpoint_recovery_version=1 AND NEW.cycle=0
        AND json_extract(NEW.input,'$.source_check_id')=src.check_id AND json_extract(NEW.input,'$.implementation_step_id')=src.implementation_id
        AND json_extract(NEW.input,'$.config_hash')=d.config_hash AND json_extract(NEW.input,'$.spec_revision_id')=d.spec_revision_id
        AND ((NEW.kind='checkpoint_snapshot' AND previous.id=p.id
          AND json_extract(NEW.input,'$.source_candidate_commit')=json_extract(c.input,'$.candidate_commit')
          AND length(json_extract(NEW.input,'$.check_id'))=36 AND json_extract(NEW.input,'$.check_id')!=json_extract(c.input,'$.workspace.check_id')
          AND json_type(NEW.input,'$.run_workspace')='object' AND (SELECT count(*) FROM json_each(NEW.input,'$.run_workspace'))=8
          AND json_extract(NEW.input,'$.run_workspace.base_commit')=json_extract(c.input,'$.candidate_commit')
          AND json_extract(NEW.input,'$.run_workspace.repo_path')=json_extract(d.intent,'$.repo_path')
          AND json_extract(NEW.input,'$.run_workspace.git_common_dir')=json_extract(d.intent,'$.git_common_dir')
          AND json_extract(NEW.input,'$.run_workspace.base_branch')=json_extract(d.intent,'$.base_branch')
          AND json_extract(NEW.input,'$.run_workspace.project_id')=json_extract(d.intent,'$.project_id')
          AND length(json_extract(NEW.input,'$.run_workspace.run_id'))=36 AND json_extract(NEW.input,'$.run_workspace.run_id')!=d.id
          AND json_extract(NEW.input,'$.run_workspace.run_id')!=(SELECT json_extract(input,'$.workspace.run_id') FROM delivery_steps WHERE id=src.implementation_id)
          AND json_extract(NEW.input,'$.run_workspace.branch')='codex/boss-run-'||json_extract(NEW.input,'$.run_workspace.run_id')
          AND json_extract(NEW.input,'$.run_workspace.path')=substr(json_extract(d.intent,'$.path'),1,length(json_extract(d.intent,'$.path'))-length(d.id))||json_extract(NEW.input,'$.run_workspace.run_id'))
        OR (NEW.kind='checkpoint_check' AND previous.kind='checkpoint_snapshot' AND previous.status='finished'
          AND json_extract(NEW.input,'$.snapshot_step_id')=previous.id AND json_extract(NEW.input,'$.plan_step_id')=json_extract(previous.input,'$.plan_step_id')
          AND json_extract(NEW.input,'$.workspace')=json_extract(previous.receipt,'$.workspace') AND json_extract(NEW.input,'$.candidate_commit')=json_extract(previous.receipt,'$.candidate_commit'))))
    BEGIN SELECT RAISE(ABORT,'checkpoint stages require exact saved source lineage'); END
    """

  defp rewrite(up?) do
    old_checked =
      "(#{transport("c")} AND json_extract(c.receipt,'$.candidate_commit')=json_extract(c.input,'$.candidate_commit') AND json_type(c.receipt,'$.output_complete')='true' AND (length(json_extract(c.receipt,'$.output_hash'))=64 AND json_extract(c.receipt,'$.output_hash') NOT GLOB '*[^0-9a-f]*') AND ((c.status='finished' AND json_extract(c.receipt,'$.exit_code')=0) OR (c.status='failed' AND json_extract(c.receipt,'$.outcome')='checks_failed' AND json_type(c.receipt,'$.exit_code')='integer' AND json_extract(c.receipt,'$.exit_code')!=0)))"

    changes =
      [
        {"execution_retry_source", "NEW.execution_recovery_version=1 AND (",
         "NEW.execution_recovery_version=1 AND NEW.checkpoint_recovery_version=0 AND ("},
        {"execution_seed_plan",
         "execution_retry_sources src ON src.implementation_id=d.retry_implementation_id",
         "retained_retry_sources src ON src.child_id=d.id AND src.implementation_id=d.retry_implementation_id"},
        {"execution_seed_receipt",
         "execution_retry_sources src ON src.implementation_id=d.retry_implementation_id",
         "retained_retry_sources src ON src.child_id=d.id AND src.implementation_id=d.retry_implementation_id"},
        {"delivery_publication_evidence",
         "execution_retry_sources src WHERE src.implementation_id=d.retry_implementation_id",
         "retained_retry_sources src WHERE src.child_id=d.id AND src.implementation_id=d.retry_implementation_id"},
        {"merge_input",
         "execution_retry_sources src WHERE src.implementation_id=d.retry_implementation_id",
         "retained_retry_sources src WHERE src.child_id=d.id AND src.implementation_id=d.retry_implementation_id"},
        {"delivery_catalog_model", "problem.kind='timeout_check'",
         "problem.kind IN ('timeout_check','checkpoint_check')"},
        {"delivery_resolution_lineage", "source.kind='timeout_check'",
         "source.kind IN ('timeout_check','checkpoint_check')"},
        {"delivery_resolution_lineage",
         "AND json_extract(source.receipt,'$.cleanup')='group_empty' AND json_extract(source.receipt,'$.exit_kind')='exit'\n  AND json_extract(source.receipt,'$.eof.stdout')=1 AND json_extract(source.receipt,'$.eof.stderr')=1",
         "AND ((json_extract(source.receipt,'$.cleanup')='group_empty' AND json_extract(source.receipt,'$.exit_kind')='exit' AND json_extract(source.receipt,'$.eof.stdout')=1 AND json_extract(source.receipt,'$.eof.stderr')=1) OR (d.checkpoint_recovery_version=1 AND source.kind IN ('check','timeout_check','checkpoint_check') AND json_type(source.receipt,'$.candidate_verified')='true' AND #{check_timeout("source")}))"},
        {"delivery_resolution_lineage", "OR (source.kind='check' AND",
         "OR (d.checkpoint_recovery_version=1 AND source.kind IN ('check','timeout_check','checkpoint_check') AND json_type(source.receipt,'$.candidate_verified')='true' AND #{check_timeout("source")}) OR (source.kind='check' AND"},
        {"delivery_resolution_lineage", "source.kind IN ('check','review','timeout_check')",
         "source.kind IN ('check','review','timeout_check','checkpoint_check')"},
        {"delivery_resolution_continuation", "tc.kind='timeout_check'",
         "tc.kind IN ('timeout_check','checkpoint_check')"},
        {"execution_retry_prefix", "c.kind='timeout_check'",
         "c.kind IN ('timeout_check','checkpoint_check')"},
        {"execution_retry_prefix", old_checked,
         "(#{old_checked} OR (EXISTS (SELECT 1 FROM deliveries owner WHERE owner.id=NEW.delivery_id AND owner.checkpoint_recovery_version=1) AND c.kind IN ('timeout_check','checkpoint_check') AND json_type(c.receipt,'$.candidate_verified')='true' AND #{check_timeout("c")}))"}
      ] ++
        for name <- ~w(delivery_step_receipt_insert delivery_step_receipt_update),
            do:
              {name, "'timeout_snapshot','timeout_check'",
               "'timeout_snapshot','timeout_check','checkpoint_snapshot','checkpoint_check'"}

    for {name, old, new} <- if(up?, do: changes, else: Enum.reverse(changes)) do
      flush()
      type = if name == "delivery_publication_evidence", do: "view", else: "trigger"

      [[sql]] =
        repo().query!("SELECT sql FROM sqlite_master WHERE type=? AND name=?", [type, name]).rows

      {from, to} = if up?, do: {old, new}, else: {new, old}

      unless String.contains?(sql, from),
        do: raise("Unexpected #{name} checkpoint recovery boundary")

      execute("DROP #{String.upcase(type)} #{name}")
      execute(String.replace(sql, from, to))
    end

    flush()
  end

  defp check_timeout(s),
    do:
      "(#{timeout(s)} AND json_type(#{s}.receipt,'$.output_complete')='false' AND json_type(#{s}.receipt,'$.output_hash')='null' AND json_extract(#{s}.receipt,'$.candidate_commit')=json_extract(#{s}.input,'$.candidate_commit'))"

  defp transport(s),
    do:
      "json_extract(#{s}.receipt,'$.cleanup')='group_empty' AND json_extract(#{s}.receipt,'$.exit_kind')='exit' AND json_type(#{s}.receipt,'$.exit_code')='integer' AND json_type(#{s}.receipt,'$.eof.stdout')='true' AND json_type(#{s}.receipt,'$.eof.stderr')='true'"

  defp passed(s), do: "(#{transport(s)} AND json_extract(#{s}.receipt,'$.exit_code')=0)"

  defp complete_check(s),
    do:
      "json_extract(#{s}.receipt,'$.candidate_commit')=json_extract(#{s}.input,'$.candidate_commit') AND json_type(#{s}.receipt,'$.output_complete')='true' AND length(json_extract(#{s}.receipt,'$.output_hash'))=64 AND json_extract(#{s}.receipt,'$.output_hash') NOT GLOB '*[^0-9a-f]*'"

  defp sha(s), do: "(length(#{s}) IN (40,64) AND #{s} NOT GLOB '*[^0-9a-f]*')"

  defp timeout(s),
    do:
      "#{s}.status='failed' AND json_extract(#{s}.receipt,'$.outcome')='timeout' AND json_extract(#{s}.receipt,'$.cleanup')='group_empty' AND json_type(#{s}.receipt,'$.eof.stdout')='true' AND json_type(#{s}.receipt,'$.eof.stderr')='true' AND ((json_extract(#{s}.receipt,'$.exit_kind')='exit' AND json_type(#{s}.receipt,'$.exit_code')='integer' AND json_extract(#{s}.receipt,'$.exit_code') BETWEEN 0 AND 2147483647 AND json_type(#{s}.receipt,'$.signal')='null') OR (json_extract(#{s}.receipt,'$.exit_kind')='signal' AND json_type(#{s}.receipt,'$.signal')='integer' AND json_extract(#{s}.receipt,'$.signal') BETWEEN 1 AND 128 AND json_type(#{s}.receipt,'$.exit_code')='null'))"

  defp implementation_base,
    do:
      "((s.cycle=1 AND d.retry_review_id IS NULL AND d.retry_implementation_id IS NULL AND previous.id=json_extract(s.input,'$.plan_step_id') AND previous.kind='plan' AND previous.status='finished' AND json_extract(s.input,'$.workspace.base_commit')=json_extract(d.intent,'$.base_commit')) OR (s.cycle=1 AND d.retry_review_id IS NOT NULL AND previous.kind='retry_check' AND json_extract(previous.input,'$.plan_step_id')=json_extract(s.input,'$.plan_step_id') AND #{transport("previous")} AND #{complete_check("previous")} AND json_extract(s.input,'$.workspace.base_commit')=json_extract(previous.input,'$.candidate_commit')) OR (previous.kind='resolve' AND previous.cycle=s.cycle-1 AND previous.status='finished' AND #{passed("previous")} AND json_type(previous.receipt,'$.report.external_action')='null' AND json_extract(previous.input,'$.plan_step_id')=json_extract(s.input,'$.plan_step_id') AND json_extract(s.input,'$.workspace.base_commit')=json_extract(previous.input,'$.candidate_commit')))"
end

defmodule Boss.Repo.Migrations.AddCheckpointRecoverySchema do
  use Ecto.Migration

  def up do
    execute(
      "ALTER TABLE deliveries ADD COLUMN checkpoint_recovery_version INTEGER NOT NULL DEFAULT 0 CHECK(checkpoint_recovery_version IN (0,1))"
    )

    execute(
      "ALTER TABLE deliveries ADD COLUMN implementation_network_version INTEGER NOT NULL DEFAULT 0 CHECK(implementation_network_version IN (0,1))"
    )

    execute(
      "ALTER TABLE deliveries ADD COLUMN retry_source_check_id TEXT REFERENCES delivery_steps(id) ON DELETE RESTRICT"
    )
  end

  def down do
    unless repo().query!(
             "SELECT count(*) FROM deliveries WHERE checkpoint_recovery_version=1 OR implementation_network_version=1 OR retry_source_check_id IS NOT NULL"
           ).rows == [[0]], do: raise("Refusing to discard checkpoint recovery history")

    execute("ALTER TABLE deliveries DROP COLUMN retry_source_check_id")
    execute("ALTER TABLE deliveries DROP COLUMN implementation_network_version")
    execute("ALTER TABLE deliveries DROP COLUMN checkpoint_recovery_version")
  end
end
