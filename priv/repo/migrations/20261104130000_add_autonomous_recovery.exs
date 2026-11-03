unless Code.ensure_loaded?(Boss.Repo.Migrations.AddReviewRetries) do
  Code.require_file("20261031220000_add_review_retries.exs", __DIR__)
end

defmodule Boss.Repo.Migrations.AddAutonomousRecovery do
  use Ecto.Migration
  alias Boss.Repo.Migrations.AddReviewRetries
  @tables ~w(deliveries delivery_requests autopilots project_intakes)

  def up do
    for table <- @tables do
      execute(
        "ALTER TABLE #{table} ADD COLUMN autonomy_version INTEGER NOT NULL DEFAULT 0 CHECK (autonomy_version IN (0,1))"
      )

      execute("""
      CREATE TRIGGER #{table}_autonomy_immutable BEFORE UPDATE OF autonomy_version ON #{table}
      WHEN NEW.autonomy_version IS NOT OLD.autonomy_version
      BEGIN SELECT RAISE(ABORT, 'autonomy policy is immutable'); END
      """)
    end

    receipt_guards(true)
    execute("DROP TRIGGER delivery_retry_stage")

    execute(
      AddReviewRetries.stage_guard(true)
      |> String.replace("NEW.number=2", "(d.autonomy_version=1 OR NEW.number=2)")
      |> String.replace("NEW.number=3", "(d.autonomy_version=1 OR NEW.number=3)")
      |> String.replace("NEW.number=4", "(d.autonomy_version=1 OR NEW.number=4)")
    )

    flush()
    replace_retry_prefix(true)

    execute("""
    CREATE TRIGGER delivery_autonomy_source BEFORE INSERT ON deliveries
    WHEN EXISTS (SELECT 1 FROM delivery_requests q WHERE q.task_id=NEW.task_id
      AND q.command_id=NEW.command_id AND q.autonomy_version!=NEW.autonomy_version)
      OR EXISTS (SELECT 1 FROM delivery_steps r JOIN deliveries d ON d.id=r.delivery_id
        WHERE r.id=NEW.retry_review_id AND d.autonomy_version!=NEW.autonomy_version)
    BEGIN SELECT RAISE(ABORT, 'delivery must retain admitted autonomy policy'); END
    """)

    execute("""
    CREATE TRIGGER autopilot_autonomy_source BEFORE INSERT ON autopilots
    WHEN EXISTS (SELECT 1 FROM project_intakes i WHERE i.project_id=NEW.project_id
      AND i.command_id=NEW.command_id AND i.autonomy_version!=NEW.autonomy_version)
    BEGIN SELECT RAISE(ABORT, 'batch must retain intake autonomy policy'); END
    """)

    execute("""
    CREATE TRIGGER autopilot_item_autonomy BEFORE INSERT ON autopilot_items
    WHEN NOT EXISTS (SELECT 1 FROM delivery_requests q JOIN autopilots b
      ON b.id=NEW.autopilot_id WHERE q.id=NEW.request_id AND q.autonomy_version=b.autonomy_version)
    BEGIN SELECT RAISE(ABORT, 'request must retain batch autonomy policy'); END
    """)

    execute(model_guard())

    execute("""
    CREATE TRIGGER delivery_resolution_required BEFORE INSERT ON delivery_steps
    WHEN NEW.kind='implement' AND NEW.cycle>1
      AND EXISTS (SELECT 1 FROM deliveries d WHERE d.id=NEW.delivery_id AND d.autonomy_version=1)
      AND NOT EXISTS (SELECT 1 FROM delivery_steps p WHERE p.delivery_id=NEW.delivery_id AND p.kind='resolve'
        AND p.number=(SELECT MAX(number) FROM delivery_steps WHERE delivery_id=NEW.delivery_id))
    BEGIN SELECT RAISE(ABORT, 'autonomous repair requires a saved resolution'); END
    """)

    execute(resolution_guard())
    execute(continuation_guard())
    execute(replan_guard())
    for operation <- ~w(INSERT UPDATE), do: execute(resolution_receipt_guard(operation))
  end

  def down do
    flush()

    for table <- @tables do
      unless repo().query!("SELECT count(*) FROM #{table} WHERE autonomy_version=1").rows == [[0]],
             do: raise("Refusing to discard autonomous workflow history")
    end

    for name <-
          ~w(delivery_autonomy_source autopilot_autonomy_source autopilot_item_autonomy delivery_model_profile delivery_resolution_required delivery_resolution_lineage delivery_resolution_continuation delivery_replan_acceptance delivery_resolution_receipt_insert delivery_resolution_receipt_update),
        do: execute("DROP TRIGGER #{name}")

    receipt_guards(false)
    execute("DROP TRIGGER delivery_retry_stage")
    execute(AddReviewRetries.stage_guard(true))
    flush()
    replace_retry_prefix(false)

    for table <- @tables do
      execute("DROP TRIGGER #{table}_autonomy_immutable")
      execute("ALTER TABLE #{table} DROP COLUMN autonomy_version")
    end
  end

  defp replace_retry_prefix(autonomous?) do
    [[sql]] =
      repo().query!(
        "SELECT sql FROM sqlite_schema WHERE type='trigger' AND name='delivery_retry_prefix'"
      ).rows

    old = "c.number=3"

    revised =
      "(c.number=3 OR EXISTS (SELECT 1 FROM deliveries d WHERE d.id=NEW.delivery_id AND d.autonomy_version=1))"

    sql =
      if autonomous?,
        do: String.replace(sql, old, revised),
        else: String.replace(sql, revised, old)

    execute("DROP TRIGGER delivery_retry_prefix")
    execute(sql)
  end

  defp receipt_guards(autonomous?) do
    kinds =
      "'plan','implement','snapshot','check','review','publish','post_check','merge','merge_check','merge_review','retry_snapshot','retry_check'"

    kinds = if autonomous?, do: kinds <> ",'resolve'", else: kinds

    cycles =
      if autonomous?,
        do:
          "(CASE (SELECT autonomy_version FROM deliveries WHERE id=NEW.delivery_id) WHEN 1 THEN 5 ELSE 3 END)",
        else: "3"

    steps =
      if autonomous?,
        do:
          "(CASE (SELECT autonomy_version FROM deliveries WHERE id=NEW.delivery_id) WHEN 1 THEN 48 ELSE 20 END)",
        else: "20"

    for operation <- ~w(INSERT UPDATE) do
      name = "delivery_step_receipt_#{String.downcase(operation)}"
      execute("DROP TRIGGER #{name}")

      execute("""
      CREATE TRIGGER #{name} BEFORE #{operation} ON delivery_steps
      WHEN NEW.cycle NOT BETWEEN 0 AND #{cycles} OR NEW.number NOT BETWEEN 1 AND #{steps}
        OR NEW.kind NOT IN (#{kinds}) OR NEW.status NOT IN ('running','finished','failed','cancelled','interrupted')
        OR (NEW.status!='running' AND (json_extract(NEW.receipt,'$.status') IS NOT NEW.status
          OR COALESCE(json_extract(NEW.receipt,'$.cleanup'),'') NOT IN ('group_empty','not_started','unknown')))
      BEGIN SELECT RAISE(ABORT, 'invalid delivery step receipt'); END
      """)
    end
  end

  defp model_guard do
    """
    CREATE TRIGGER delivery_model_profile BEFORE INSERT ON delivery_steps
    WHEN NEW.kind IN ('plan','implement','review','merge_review','resolve')
      AND EXISTS (SELECT 1 FROM deliveries d WHERE d.id=NEW.delivery_id AND d.autonomy_version=1
        AND (d.reviewer!='claude' OR NEW.kind NOT IN ('review','merge_review')))
      AND NOT COALESCE((
        json_type(NEW.input,'$.model_profile')='object'
        AND (SELECT count(*) FROM json_each(NEW.input,'$.model_profile'))=2
        AND EXISTS (SELECT 1 FROM (
          SELECT model, effort FROM (
          SELECT
          CASE WHEN NEW.kind='plan' AND EXISTS (SELECT 1 FROM delivery_steps p WHERE p.id=json_extract(NEW.input,'$.plan_step_id') AND p.delivery_id=NEW.delivery_id AND p.kind='plan' AND p.status='failed' AND json_extract(p.receipt,'$.outcome') IN ('invalid_report','exited')) THEN
            CASE WHEN (SELECT json_extract(p.input,'$.model_profile.model') FROM delivery_steps p WHERE p.id=json_extract(NEW.input,'$.plan_step_id'))='gpt-6-astra' THEN 'gpt-6.1-sol' ELSE 'gpt-6-astra' END
            WHEN NEW.kind='resolve' AND json_extract(NEW.input,'$.resolution_attempt')=1 THEN 'gpt-6-astra'
            WHEN NEW.kind='resolve' THEN 'gpt-6.1-sol'
            WHEN NEW.kind='implement' AND NEW.cycle IN (2,4) THEN 'gpt-6-astra'
            WHEN NEW.kind='implement' AND NEW.cycle=1 AND EXISTS (SELECT 1 FROM delivery_steps p
              WHERE p.id=json_extract(NEW.input,'$.plan_step_id') AND p.delivery_id=NEW.delivery_id
                AND json_extract(p.receipt,'$.report.complexity')='small') THEN 'gpt-6-luna'
            ELSE 'gpt-6.1-sol' END AS model,
          CASE WHEN NEW.kind='plan' AND EXISTS (SELECT 1 FROM delivery_steps p WHERE p.id=json_extract(NEW.input,'$.plan_step_id') AND p.delivery_id=NEW.delivery_id AND p.kind='plan' AND p.status='failed' AND json_extract(p.receipt,'$.outcome') IN ('invalid_report','exited')) THEN 'xhigh'
            WHEN NEW.kind='resolve' OR (NEW.kind='implement' AND NEW.cycle>1) THEN 'xhigh'
            WHEN NEW.kind='implement' AND NEW.cycle=1 AND EXISTS (SELECT 1 FROM delivery_steps p
              WHERE p.id=json_extract(NEW.input,'$.plan_step_id') AND p.delivery_id=NEW.delivery_id
                AND json_extract(p.receipt,'$.report.complexity')='small') THEN 'medium'
            ELSE 'high' END AS effort, 0 AS priority
          UNION ALL SELECT 'gpt-6.1-sol', 'xhigh', 1
          UNION ALL SELECT 'gpt-6-astra', 'xhigh', 2
          ) routes
          WHERE NOT EXISTS (SELECT 1 FROM delivery_steps failed WHERE failed.delivery_id=NEW.delivery_id
            AND failed.kind IN ('plan','implement','review','merge_review','resolve')
            AND #{unavailable_model("failed")} AND #{transport("failed")}
            AND json_extract(failed.input,'$.model_profile.model')=routes.model)
          AND NOT (NEW.kind='resolve' AND json_extract(NEW.input,'$.resolution_attempt')=2
            AND routes.model=(SELECT json_extract(previous.input,'$.model_profile.model') FROM delivery_steps previous
              WHERE previous.delivery_id=NEW.delivery_id ORDER BY previous.number DESC LIMIT 1))
          ORDER BY priority LIMIT 1
        ) selected
          WHERE json_extract(NEW.input,'$.model_profile.model')=selected.model
            AND json_extract(NEW.input,'$.model_profile.reasoning_effort')=selected.effort)), 0)
    BEGIN SELECT RAISE(ABORT, 'model selection must match the saved autonomy policy'); END
    """
  end

  defp resolution_guard do
    """
    CREATE TRIGGER delivery_resolution_lineage BEFORE INSERT ON delivery_steps
    WHEN NEW.kind='resolve' AND NOT EXISTS (
      SELECT 1 FROM deliveries d
      JOIN delivery_steps source ON source.id=json_extract(NEW.input,'$.source_step_id') AND source.delivery_id=d.id
      JOIN delivery_steps previous ON previous.delivery_id=d.id
        AND previous.number=(SELECT MAX(number) FROM delivery_steps WHERE delivery_id=d.id)
      WHERE d.id=NEW.delivery_id AND d.autonomy_version=1 AND d.cleanup!='unknown'
      AND NEW.number=previous.number+1 AND NEW.cycle=source.cycle AND NEW.cycle<5
      AND json_extract(NEW.input,'$.parent_step_id')=previous.id
      AND json_extract(NEW.input,'$.config_hash')=d.config_hash
      AND json_extract(NEW.input,'$.spec_revision_id')=d.spec_revision_id
      AND length(json_extract(NEW.input,'$.input_hash'))=64 AND length(json_extract(NEW.input,'$.feedback_hash'))=64
      AND #{transport("source")}
      AND ((source.kind='plan' AND ((source.status='finished' AND json_extract(source.receipt,'$.exit_code')=0
          AND json_type(source.receipt,'$.report.clarification')='text') OR #{model_failure("source")}))
        OR (source.kind='review' AND ((source.status='finished' AND json_extract(source.receipt,'$.exit_code')=0
          AND json_extract(source.receipt,'$.report.verdict') IN ('changes_requested','needs_spec_revision')) OR #{model_failure("source")}))
        OR (source.kind='implement' AND #{unavailable_model("source")})
        OR (source.kind='check' AND source.status='failed' AND json_extract(source.receipt,'$.outcome')='checks_failed'
          AND json_extract(source.receipt,'$.output_complete')=1 AND json_type(source.receipt,'$.exit_code')='integer'
          AND json_extract(source.receipt,'$.exit_code')!=0))
      AND ((json_extract(NEW.input,'$.resolution_attempt')=1 AND previous.id=source.id)
        OR (json_extract(NEW.input,'$.resolution_attempt')=2 AND previous.kind='resolve'
          AND previous.cycle=source.cycle AND json_extract(previous.input,'$.resolution_attempt')=1
          AND json_extract(previous.input,'$.source_step_id')=source.id AND #{transport("previous")}
          AND ((previous.status='finished' AND json_type(previous.receipt,'$.report.external_action')='text')
            OR #{model_failure("previous")})))
      AND ((source.kind='plan' AND json_extract(NEW.input,'$.plan_step_id')=source.id
        AND json_extract(NEW.input,'$.workspace')=d.intent
        AND json_extract(NEW.input,'$.candidate_commit')=json_extract(d.intent,'$.base_commit')
        AND (SELECT count(*) FROM delivery_steps p WHERE p.delivery_id=d.id AND p.kind='plan')<3)
      OR (source.kind IN ('check','review')
        AND json_extract(NEW.input,'$.plan_step_id')=json_extract(source.input,'$.plan_step_id')
        AND json_extract(NEW.input,'$.workspace')=json_extract(source.input,'$.workspace')
        AND json_extract(NEW.input,'$.candidate_commit')=json_extract(source.input,'$.candidate_commit'))
      OR (source.kind='implement' AND #{implementation_resolution_workspace()})))
    BEGIN SELECT RAISE(ABORT, 'resolution must follow its saved recoverable source'); END
    """
  end

  defp continuation_guard do
    """
    CREATE TRIGGER delivery_resolution_continuation BEFORE INSERT ON delivery_steps
    WHEN (NEW.kind='plan' AND NEW.number>1) OR
      (NEW.kind='implement' AND EXISTS (SELECT 1 FROM delivery_steps p WHERE p.delivery_id=NEW.delivery_id
        AND p.number=(SELECT MAX(number) FROM delivery_steps WHERE delivery_id=NEW.delivery_id) AND p.kind='resolve'))
    BEGIN
      SELECT CASE WHEN NOT EXISTS (SELECT 1 FROM deliveries d JOIN delivery_steps p ON p.delivery_id=d.id
        WHERE d.id=NEW.delivery_id AND d.autonomy_version=1
        AND p.number=(SELECT MAX(number) FROM delivery_steps WHERE delivery_id=d.id)
        AND NEW.number=p.number+1 AND p.kind='resolve' AND p.status='finished' AND #{transport("p")}
        AND json_extract(p.receipt,'$.exit_code')=0 AND json_type(p.receipt,'$.report.external_action')='null'
        AND json_extract(NEW.input,'$.parent_step_id')=p.id
        AND json_extract(NEW.input,'$.plan_step_id')=json_extract(p.input,'$.plan_step_id')
        AND ((NEW.kind='plan' AND NEW.cycle=0 AND p.cycle=0 AND json_extract(NEW.input,'$.workspace')=d.intent
          AND (SELECT count(*) FROM delivery_steps t WHERE t.delivery_id=d.id AND t.kind='plan')<3)
        OR (NEW.kind='implement' AND p.cycle>0 AND NEW.cycle=p.cycle+1 AND NEW.cycle<=5
          AND json_extract(NEW.input,'$.resolution_step_id')=p.id
          AND json_extract(NEW.input,'$.source_step_id')=json_extract(p.input,'$.source_step_id')
          AND json_extract(NEW.input,'$.workspace.base_commit')=json_extract(p.input,'$.candidate_commit'))))
      THEN RAISE(ABORT, 'continuation requires a completed resolution') END;
    END
    """
  end

  defp replan_guard do
    """
    CREATE TRIGGER delivery_replan_acceptance BEFORE UPDATE ON delivery_steps
    WHEN NEW.kind='plan' AND NEW.status='finished' AND EXISTS (SELECT 1 FROM delivery_steps p
      WHERE p.delivery_id=NEW.delivery_id AND p.kind='plan' AND p.status='finished' AND p.number<NEW.number
      AND json_array_length(p.receipt,'$.report.acceptance')>0
      AND (json_type(NEW.receipt,'$.report.acceptance') IS NOT 'array'
        OR json_array_length(NEW.receipt,'$.report.acceptance')!=json_array_length(p.receipt,'$.report.acceptance')
        OR EXISTS (SELECT 1 FROM json_each(p.receipt,'$.report.acceptance') old
          WHERE NOT EXISTS (SELECT 1 FROM json_each(NEW.receipt,'$.report.acceptance') fresh
            WHERE fresh.type='text' AND fresh.value=old.value))))
    BEGIN SELECT RAISE(ABORT, 'replanning cannot weaken saved acceptance criteria'); END
    """
  end

  defp resolution_receipt_guard(operation) do
    """
    CREATE TRIGGER delivery_resolution_receipt_#{String.downcase(operation)} BEFORE #{operation} ON delivery_steps
    WHEN NEW.kind='resolve' AND NEW.status='finished' AND NOT COALESCE((
      #{transport("NEW")} AND json_extract(NEW.receipt,'$.exit_code')=0
      AND json_extract(NEW.receipt,'$.candidate_commit')=json_extract(NEW.input,'$.candidate_commit')
      AND json_type(NEW.receipt,'$.report')='object'
      AND length(CAST(json_extract(NEW.receipt,'$.report') AS BLOB)) BETWEEN 1 AND 32768
      AND (SELECT count(*) FROM json_each(NEW.receipt,'$.report'))=4
      AND (SELECT count(DISTINCT key) FROM json_each(NEW.receipt,'$.report'))=4
      AND NOT EXISTS (SELECT 1 FROM json_each(NEW.receipt,'$.report') WHERE key NOT IN ('summary','steps','assumptions','external_action'))
      AND json_type(NEW.receipt,'$.report.summary')='text'
      AND length(CAST(json_extract(NEW.receipt,'$.report.summary') AS BLOB)) BETWEEN 1 AND 2000
      AND length(trim(json_extract(NEW.receipt,'$.report.summary')))>0
      AND instr(json_extract(NEW.receipt,'$.report.summary'),char(0))=0
      AND json_type(NEW.receipt,'$.report.steps')='array' AND json_array_length(NEW.receipt,'$.report.steps') BETWEEN 1 AND 20
      AND NOT EXISTS (SELECT 1 FROM json_each(NEW.receipt,'$.report.steps') WHERE type!='text'
        OR length(CAST(value AS BLOB)) NOT BETWEEN 1 AND 2000 OR length(trim(value))=0 OR instr(value,char(0))>0)
      AND json_type(NEW.receipt,'$.report.assumptions')='array' AND json_array_length(NEW.receipt,'$.report.assumptions') BETWEEN 0 AND 20
      AND NOT EXISTS (SELECT 1 FROM json_each(NEW.receipt,'$.report.assumptions') WHERE type!='text'
        OR length(CAST(value AS BLOB)) NOT BETWEEN 1 AND 1000 OR length(trim(value))=0 OR instr(value,char(0))>0)
      AND (json_type(NEW.receipt,'$.report.external_action')='null'
        OR (json_type(NEW.receipt,'$.report.external_action')='text'
          AND length(CAST(json_extract(NEW.receipt,'$.report.external_action') AS BLOB)) BETWEEN 1 AND 500
          AND length(trim(json_extract(NEW.receipt,'$.report.external_action')))>0
          AND instr(json_extract(NEW.receipt,'$.report.external_action'),char(0))=0))), 0)
    BEGIN SELECT RAISE(ABORT, 'invalid autonomous resolution report'); END
    """
  end

  defp transport(s),
    do: """
    json_extract(#{s}.receipt,'$.cleanup')='group_empty' AND json_extract(#{s}.receipt,'$.exit_kind')='exit'
      AND json_extract(#{s}.receipt,'$.eof.stdout')=1 AND json_extract(#{s}.receipt,'$.eof.stderr')=1
    """

  defp model_failure(s),
    do:
      "(#{s}.status='failed' AND json_extract(#{s}.receipt,'$.outcome') IN ('invalid_report','exited') AND json_type(#{s}.receipt,'$.exit_code')='integer')"

  defp unavailable_model(s),
    do: """
    (#{s}.status='failed' AND json_extract(#{s}.receipt,'$.outcome')='exited'
      AND json_type(#{s}.receipt,'$.exit_code')='integer' AND json_extract(#{s}.receipt,'$.exit_code')!=0)
    """

  defp implementation_resolution_workspace do
    identity =
      Enum.map_join(~w(project_id repo_path git_common_dir base_branch), " AND ", fn key ->
        "json_extract(NEW.input,'$.workspace.#{key}')=json_extract(d.intent,'$.#{key}')"
      end)

    """
    json_extract(NEW.input,'$.plan_step_id')=json_extract(source.input,'$.plan_step_id')
    AND json_type(NEW.input,'$.workspace')='object'
    AND (SELECT count(*) FROM json_each(NEW.input,'$.workspace'))=8
    AND #{identity}
    AND length(json_extract(NEW.input,'$.workspace.run_id'))=36
    AND length(json_extract(source.input,'$.workspace.base_commit')) IN (40,64)
    AND json_extract(NEW.input,'$.workspace.base_commit')=json_extract(source.input,'$.workspace.base_commit')
    AND json_extract(NEW.input,'$.candidate_commit')=json_extract(source.input,'$.workspace.base_commit')
    AND json_extract(NEW.input,'$.workspace.branch')='codex/boss-run-' || json_extract(NEW.input,'$.workspace.run_id')
    AND json_extract(NEW.input,'$.workspace.path')=
      substr(json_extract(source.input,'$.workspace.path'),1,
        length(json_extract(source.input,'$.workspace.path'))-length(json_extract(source.input,'$.workspace.run_id')))
      || json_extract(NEW.input,'$.workspace.run_id')
    AND json_extract(NEW.input,'$.workspace.path')!=json_extract(source.input,'$.workspace.path')
    AND json_extract(NEW.input,'$.workspace.path')!=json_extract(d.intent,'$.path')
    AND ((json_extract(NEW.input,'$.resolution_attempt')=2
      AND json_extract(NEW.input,'$.workspace')=json_extract(previous.input,'$.workspace'))
      OR (json_extract(NEW.input,'$.resolution_attempt')=1 AND NOT EXISTS (
        SELECT 1 FROM delivery_steps old WHERE old.delivery_id=d.id
          AND (json_extract(old.input,'$.workspace.path')=json_extract(NEW.input,'$.workspace.path')
            OR json_extract(old.receipt,'$.workspace.path')=json_extract(NEW.input,'$.workspace.path')
            OR json_extract(old.input,'$.workspace.branch')=json_extract(NEW.input,'$.workspace.branch')
            OR json_extract(old.receipt,'$.workspace.branch')=json_extract(NEW.input,'$.workspace.branch')))))
    """
  end
end
