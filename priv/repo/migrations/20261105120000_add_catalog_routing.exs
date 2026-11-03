defmodule Boss.Repo.Migrations.AddCatalogRouting do
  use Ecto.Migration
  @tables ~w(deliveries delivery_requests autopilots project_intakes)
  @strong "'gpt-6.1-sol','gpt-6-astra','gpt-5.6-sol','gpt-5.6-terra'"
  @small "'gpt-6-luna','gpt-5.6-luna'"
  @codes "'catalog_unavailable','catalog_invalid','catalog_insufficient_models','codex_unavailable','models_exhausted','provider_auth','provider_rate_limit','provider_schema','provider_transport'"
  @shared "'auth','rate_limit','schema','transport'"

  def up do
    for table <- @tables do
      execute(
        "ALTER TABLE #{table} ADD COLUMN routing_version INTEGER NOT NULL DEFAULT 1 CHECK (routing_version IN (1,2))"
      )

      execute("""
      CREATE TRIGGER #{table}_routing_immutable BEFORE UPDATE OF routing_version ON #{table}
      WHEN NEW.routing_version IS NOT OLD.routing_version
      BEGIN SELECT RAISE(ABORT, 'routing policy is immutable'); END
      """)

      execute("""
      CREATE TRIGGER #{table}_routing_initial BEFORE INSERT ON #{table}
      WHEN NEW.routing_version=2 AND NEW.autonomy_version!=1
      BEGIN SELECT RAISE(ABORT, 'catalog routing requires autonomous admission'); END
      """)
    end

    for table <- ~w(deliveries project_intakes) do
      execute("ALTER TABLE #{table} ADD COLUMN model_catalog TEXT NOT NULL DEFAULT '{}'")
      for operation <- ~w(INSERT UPDATE), do: execute(catalog_guard(table, operation))
    end

    execute(
      "ALTER TABLE deliveries ADD COLUMN failure_code TEXT CHECK (failure_code IS NULL OR failure_code IN (#{@codes}))"
    )

    execute("""
    CREATE TRIGGER intake_catalog_required BEFORE UPDATE OF workspace ON project_intakes
    WHEN NEW.workspace!=OLD.workspace AND NEW.routing_version=2 AND NEW.model_catalog='{}'
    BEGIN SELECT RAISE(ABORT, 'intake must pin its catalog before workspace effects'); END
    """)

    execute("""
    CREATE TRIGGER delivery_failure_code_initial BEFORE INSERT ON deliveries
    WHEN NEW.failure_code IS NOT NULL
    BEGIN SELECT RAISE(ABORT, 'failure diagnosis requires a terminal receipt'); END
    """)

    execute("""
    CREATE TRIGGER delivery_failure_code_immutable BEFORE UPDATE OF failure_code ON deliveries
    WHEN NEW.failure_code IS NOT OLD.failure_code AND (OLD.status NOT IN ('planning','implementing','testing','reviewing','integrating')
      OR NEW.status NOT IN ('failed','blocked','needs_input'))
    BEGIN SELECT RAISE(ABORT, 'terminal failure diagnosis is immutable'); END
    """)

    execute("""
    CREATE TRIGGER delivery_routing_source BEFORE INSERT ON deliveries
    WHEN EXISTS (SELECT 1 FROM delivery_requests q WHERE q.task_id=NEW.task_id AND q.command_id=NEW.command_id AND q.routing_version!=NEW.routing_version)
      OR EXISTS (SELECT 1 FROM delivery_steps r JOIN deliveries p ON p.id=r.delivery_id WHERE r.id=NEW.retry_review_id
        AND (p.routing_version!=NEW.routing_version OR p.model_catalog!=NEW.model_catalog))
    BEGIN SELECT RAISE(ABORT, 'delivery must retain saved routing inputs'); END
    """)

    execute("""
    CREATE TRIGGER autopilot_routing_source BEFORE INSERT ON autopilots
    WHEN EXISTS (SELECT 1 FROM project_intakes i WHERE i.project_id=NEW.project_id AND i.command_id=NEW.command_id AND i.routing_version!=NEW.routing_version)
    BEGIN SELECT RAISE(ABORT, 'batch must retain saved intake routing'); END
    """)

    execute("""
    CREATE TRIGGER autopilot_item_routing BEFORE INSERT ON autopilot_items
    WHEN NOT EXISTS (SELECT 1 FROM delivery_requests q JOIN autopilots b ON b.id=NEW.autopilot_id
      WHERE q.id=NEW.request_id AND q.routing_version=b.routing_version)
    BEGIN SELECT RAISE(ABORT, 'request must retain saved batch routing'); END
    """)

    execute(recovery_view())
    flush()
    rewrite_trigger("autopilot_insert", "t.state='new'", selection())

    rewrite_trigger(
      "delivery_model_profile",
      "d.autonomy_version=1",
      "d.autonomy_version=1 AND d.routing_version=1"
    )

    rewrite_trigger(
      "delivery_resolution_lineage",
      "AND json_extract(source.receipt,'$.exit_code')!=0",
      extended_implementation_exit()
    )

    rewrite_trigger(
      "delivery_resolution_lineage",
      "AND d.cleanup!='unknown'",
      "AND d.cleanup!='unknown' " <> provider_gate()
    )

    rewrite_trigger(
      "autopilot_delivery_guard",
      "AND d.integration_command_id IS NULL)",
      "AND d.integration_command_id IS NULL AND NOT (#{shared_delivery_failure()}))"
    )

    execute(model_guard())
  end

  def down do
    flush()

    for table <- @tables do
      unless repo().query!("SELECT count(*) FROM #{table} WHERE routing_version=2").rows == [[0]],
        do: raise("Refusing to discard catalog routing history")
    end

    unless repo().query!("SELECT count(*) FROM deliveries WHERE failure_code IS NOT NULL").rows ==
             [[0]],
           do: raise("Refusing to discard provider failure history")

    for table <- @tables,
        suffix <- ~w(immutable initial),
        do: execute("DROP TRIGGER #{table}_routing_#{suffix}")

    for table <- ~w(deliveries project_intakes),
        operation <- ~w(insert update),
        do: execute("DROP TRIGGER #{table}_catalog_#{operation}")

    for name <-
          ~w(intake_catalog_required delivery_failure_code_initial delivery_failure_code_immutable delivery_routing_source autopilot_routing_source autopilot_item_routing delivery_catalog_model),
        do: execute("DROP TRIGGER #{name}")

    rewrite_trigger("autopilot_insert", selection(), "t.state='new'")

    rewrite_trigger(
      "delivery_model_profile",
      "d.autonomy_version=1 AND d.routing_version=1",
      "d.autonomy_version=1"
    )

    rewrite_trigger(
      "delivery_resolution_lineage",
      extended_implementation_exit(),
      "AND json_extract(source.receipt,'$.exit_code')!=0"
    )

    rewrite_trigger(
      "delivery_resolution_lineage",
      "AND d.cleanup!='unknown' " <> provider_gate(),
      "AND d.cleanup!='unknown'"
    )

    rewrite_trigger(
      "autopilot_delivery_guard",
      "AND d.integration_command_id IS NULL AND NOT (#{shared_delivery_failure()}))",
      "AND d.integration_command_id IS NULL)"
    )

    execute("DROP VIEW autopilot_recovery_candidates")

    for table <- ~w(deliveries project_intakes),
        do: execute("ALTER TABLE #{table} DROP COLUMN model_catalog")

    execute("ALTER TABLE deliveries DROP COLUMN failure_code")
    for table <- @tables, do: execute("ALTER TABLE #{table} DROP COLUMN routing_version")
  end

  defp rewrite_trigger(name, before, after_sql) do
    flush()

    [[sql]] =
      repo().query!("SELECT sql FROM sqlite_schema WHERE type='trigger' AND name=?", [name]).rows

    unless String.contains?(sql, before),
      do: raise("Expected #{name} migration boundary was not found")

    execute("DROP TRIGGER #{name}")
    execute(String.replace(sql, before, after_sql))
    flush()
  end

  defp catalog_guard(table, operation) do
    initial = if table == "deliveries", do: "NEW.retry_review_id IS NULL", else: "1"

    stage_gate =
      if table == "deliveries",
        do: "EXISTS (SELECT 1 FROM delivery_steps WHERE delivery_id=OLD.id)",
        else: "OLD.workspace!='{}' OR OLD.stop_requested=1"

    mutation =
      if operation == "INSERT" do
        "(NEW.model_catalog!='{}' AND (#{initial}))"
      else
        "(NEW.model_catalog!=OLD.model_catalog AND (OLD.model_catalog!='{}' OR NEW.status!='planning' OR #{stage_gate}))"
      end

    """
    CREATE TRIGGER #{table}_catalog_#{String.downcase(operation)} BEFORE #{operation} ON #{table}
    WHEN #{mutation} OR (NEW.model_catalog!='{}' AND (NEW.routing_version!=2 OR NOT COALESCE((#{catalog_valid("NEW.model_catalog")}),0)))
    BEGIN SELECT RAISE(ABORT, 'model catalog must be validated and pinned before effects'); END
    """
  end

  defp profile_valid(value, models) do
    """
    json_type(#{value})='object' AND (SELECT count(*) FROM json_each(#{value}))=2
      AND (SELECT count(DISTINCT key) FROM json_each(#{value}))=2
      AND json_extract(#{value},'$.model') IN (#{models})
      AND json_extract(#{value},'$.reasoning_effort') IN ('medium','high','xhigh')
    """
  end

  defp effort(value),
    do: "CASE #{value} WHEN 'medium' THEN 1 WHEN 'high' THEN 2 WHEN 'xhigh' THEN 3 ELSE 0 END"

  defp catalog_valid(c) do
    primary = "json_extract(#{c},'$.primary')"
    resolver = "json_extract(#{c},'$.resolver')"
    small = "json_extract(#{c},'$.small')"

    """
    json_valid(#{c}) AND json_type(#{c})='object'
      AND (SELECT count(*) FROM json_each(#{c}))=5 AND (SELECT count(DISTINCT key) FROM json_each(#{c}))=5
      AND NOT EXISTS (SELECT 1 FROM json_each(#{c}) WHERE key NOT IN ('version','primary','resolver','small','fallbacks'))
      AND json_type(#{c},'$.version')='integer' AND json_extract(#{c},'$.version')=2
      AND (#{profile_valid(primary, @strong)}) AND (#{profile_valid(resolver, @strong)})
      AND json_extract(#{c},'$.primary.model')!=json_extract(#{c},'$.resolver.model')
      AND (json_type(#{c},'$.small')='null' OR (#{profile_valid(small, @small)}))
      AND json_type(#{c},'$.fallbacks')='array' AND json_array_length(#{c},'$.fallbacks') BETWEEN 2 AND 4
      AND NOT EXISTS (SELECT 1 FROM json_each(#{c},'$.fallbacks') f WHERE NOT COALESCE((#{profile_valid("f.value", @strong)}),0))
      AND (SELECT count(DISTINCT json_extract(value,'$.model')) FROM json_each(#{c},'$.fallbacks'))=json_array_length(#{c},'$.fallbacks')
      AND json_extract(#{c},'$.fallbacks[0].model')=json_extract(#{c},'$.primary.model')
      AND #{effort("json_extract(#{c},'$.fallbacks[0].reasoning_effort')")}>=#{effort("json_extract(#{c},'$.primary.reasoning_effort')")}
      AND json_extract(#{c},'$.fallbacks[1].model')=json_extract(#{c},'$.resolver.model')
      AND json_extract(#{c},'$.fallbacks[1].reasoning_effort')=json_extract(#{c},'$.resolver.reasoning_effort')
    """
  end

  defp model_guard do
    preferred = """
    CASE WHEN NEW.kind='plan' AND EXISTS (SELECT 1 FROM delivery_steps p WHERE p.id=json_extract(NEW.input,'$.plan_step_id')
      AND p.delivery_id=d.id AND p.kind='plan' AND p.status='failed' AND json_extract(p.receipt,'$.outcome') IN ('invalid_report','exited'))
      THEN CASE WHEN (SELECT json_extract(p.input,'$.model_profile.model') FROM delivery_steps p WHERE p.id=json_extract(NEW.input,'$.plan_step_id'))=json_extract(d.model_catalog,'$.resolver.model')
        THEN json_extract(d.model_catalog,'$.fallbacks[0]') ELSE json_extract(d.model_catalog,'$.resolver') END
      WHEN NEW.kind='resolve' AND json_extract(NEW.input,'$.resolution_attempt')=1 THEN json_extract(d.model_catalog,'$.resolver')
      WHEN NEW.kind='resolve' OR (NEW.kind='implement' AND NEW.cycle IN (3,5)) THEN json_extract(d.model_catalog,'$.fallbacks[0]')
      WHEN NEW.kind='implement' AND NEW.cycle IN (2,4) THEN json_extract(d.model_catalog,'$.resolver')
      WHEN NEW.kind='implement' AND NEW.cycle=1 AND json_type(d.model_catalog,'$.small')='object'
        AND EXISTS (SELECT 1 FROM delivery_steps p WHERE p.id=json_extract(NEW.input,'$.plan_step_id') AND p.delivery_id=d.id AND json_extract(p.receipt,'$.report.complexity')='small')
        THEN json_extract(d.model_catalog,'$.small') ELSE json_extract(d.model_catalog,'$.primary') END
    """

    """
    CREATE TRIGGER delivery_catalog_model BEFORE INSERT ON delivery_steps
    WHEN NEW.kind IN ('plan','implement','review','merge_review','resolve') AND EXISTS (
      SELECT 1 FROM deliveries d WHERE d.id=NEW.delivery_id AND d.routing_version=2
        AND (d.reviewer!='claude' OR NEW.kind NOT IN ('review','merge_review'))
        AND NOT COALESCE((d.model_catalog!='{}' AND #{profile_valid("json_extract(NEW.input,'$.model_profile')", @strong <> "," <> @small)}
          AND EXISTS (SELECT 1 FROM (
            SELECT profile FROM (SELECT #{preferred} AS profile,0 AS priority
              UNION ALL SELECT value AS profile,cast(key AS INTEGER)+1 AS priority FROM json_each(d.model_catalog,'$.fallbacks')) routes
            WHERE NOT EXISTS (SELECT 1 FROM delivery_steps failed WHERE failed.delivery_id=d.id
              AND failed.kind IN ('plan','implement','review','merge_review','resolve') AND failed.status='failed'
              AND json_extract(failed.receipt,'$.outcome')='exited' AND json_type(failed.receipt,'$.exit_code')='integer'
              AND #{transport("failed")} AND json_extract(failed.receipt,'$.summary.error_class')='model_unavailable'
              AND json_extract(failed.input,'$.model_profile.model')=json_extract(routes.profile,'$.model'))
              AND NOT (NEW.kind='resolve' AND json_extract(NEW.input,'$.resolution_attempt')=2
                AND json_extract(routes.profile,'$.model')=(SELECT json_extract(p.input,'$.model_profile.model') FROM delivery_steps p WHERE p.delivery_id=d.id ORDER BY p.number DESC LIMIT 1))
            ORDER BY priority LIMIT 1
          ) selected WHERE json_extract(NEW.input,'$.model_profile.model')=json_extract(selected.profile,'$.model')
            AND json_extract(NEW.input,'$.model_profile.reasoning_effort')=json_extract(selected.profile,'$.reasoning_effort'))),0))
    BEGIN SELECT RAISE(ABORT, 'model selection must match the pinned catalog'); END
    """
  end

  defp recovery_view do
    """
    CREATE VIEW autopilot_recovery_candidates AS
    SELECT t.id AS task_id,s.project_id AS project_id FROM tasks t JOIN specs s ON s.id=t.spec_id
    WHERE s.missing=0 AND t.state IN ('new','failed','blocked','needs_input')
      AND NOT EXISTS (SELECT 1 FROM delivery_requests r WHERE r.task_id=t.id AND r.status IN ('queued','paused'))
      AND NOT EXISTS (SELECT 1 FROM agent_runs r WHERE r.task_id=t.id AND (r.status IN ('preparing','launching','running','stopping') OR r.cleanup='unknown'))
      AND NOT EXISTS (SELECT 1 FROM deliveries d WHERE d.task_id=t.id AND (d.status IN ('planning','implementing','testing','reviewing','integrating') OR d.cleanup='unknown'
        OR (d.status!='done' AND (d.integration_intent!='{}' OR d.integration_command_id IS NOT NULL))))
    """
  end

  defp selection,
    do:
      "((NEW.routing_version=1 AND t.state='new') OR (NEW.routing_version=2 AND t.id IN (SELECT task_id FROM autopilot_recovery_candidates)))"

  defp extended_implementation_exit,
    do:
      "AND (json_extract(source.receipt,'$.exit_code')!=0 OR (d.routing_version=2 AND json_extract(source.receipt,'$.summary.error_class') IN ('model_unavailable','unknown')))"

  defp provider_gate,
    do:
      "AND NOT (d.routing_version=2 AND (COALESCE(json_extract(source.receipt,'$.summary.error_class'),'') IN (#{@shared}) OR (json_extract(NEW.input,'$.resolution_attempt')=2 AND COALESCE(json_extract(previous.receipt,'$.summary.error_class'),'') IN (#{@shared}))))"

  defp transport(s),
    do:
      "json_extract(#{s}.receipt,'$.cleanup')='group_empty' AND json_extract(#{s}.receipt,'$.exit_kind')='exit' AND json_extract(#{s}.receipt,'$.eof.stdout')=1 AND json_extract(#{s}.receipt,'$.eof.stderr')=1"

  defp shared_delivery_failure do
    """
    COALESCE(d.failure_code,'') IN (#{@codes}) OR (d.routing_version=1 AND d.autonomy_version=1
      AND (SELECT count(DISTINCT json_extract(f.input,'$.model_profile.model')) FROM delivery_steps f
        WHERE f.delivery_id=d.id AND f.kind IN ('plan','implement','review','merge_review','resolve') AND f.status='failed'
          AND json_extract(f.input,'$.model_profile.model') IN ('gpt-6.1-sol','gpt-6-astra')
          AND json_extract(f.receipt,'$.outcome')='exited' AND json_type(f.receipt,'$.exit_code')='integer'
          AND json_extract(f.receipt,'$.exit_code')!=0 AND #{transport("f")})=2)
    """
  end
end
