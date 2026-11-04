defmodule Boss.Repo.Migrations.AddProviderRecovery do
  use Ecto.Migration

  def up do
    Boss.Repo.Migrations.AddProviderRecoverySchema.up()
    flush()
    provider_sources()
    rewrite(true)

    execute("""
    CREATE TRIGGER provider_recovery_immutable BEFORE UPDATE ON deliveries
    WHEN NEW.provider_recovery_version IS NOT OLD.provider_recovery_version
    BEGIN SELECT RAISE(ABORT,'provider recovery policy is immutable'); END
    """)

    execute("""
    CREATE TRIGGER provider_recovery_source BEFORE INSERT ON deliveries
    WHEN NEW.provider_recovery_version=1 AND (
      NEW.checkpoint_recovery_version!=1 OR NEW.execution_recovery_version!=1 OR NEW.implementation_network_version!=1
      OR NEW.retry_source_check_id IS NOT NULL OR NEW.retry_review_id IS NOT NULL OR NEW.retry_candidate_commit IS NOT NULL
      OR NOT EXISTS (SELECT 1 FROM provider_retry_sources src JOIN deliveries p ON p.id=src.parent_id
        WHERE src.implementation_id=NEW.retry_implementation_id
          AND NEW.project_id=p.project_id AND NEW.task_id=p.task_id AND NEW.spec_revision_id=p.spec_revision_id
          AND NEW.admitted_version=src.terminal_version AND NEW.check_config=p.check_config AND NEW.config_hash=p.config_hash
          AND NEW.reviewer=p.reviewer AND NEW.autonomy_version=p.autonomy_version AND NEW.routing_version=p.routing_version
          AND NEW.model_catalog=p.model_catalog))
    BEGIN SELECT RAISE(ABORT,'provider recovery requires its exact terminal rate-limit source'); END
    """)

    execute("""
    CREATE TRIGGER provider_checkpoint_stage BEFORE INSERT ON delivery_steps
    WHEN NEW.kind IN ('checkpoint_snapshot','checkpoint_check')
      AND EXISTS (SELECT 1 FROM deliveries WHERE id=NEW.delivery_id AND provider_recovery_version=1)
      AND NOT EXISTS (
        SELECT 1 FROM deliveries d
        JOIN provider_retry_sources src ON src.implementation_id=d.retry_implementation_id
        JOIN delivery_steps s ON s.id=src.implementation_id
        JOIN delivery_steps p ON p.id=json_extract(NEW.input,'$.plan_step_id') AND p.delivery_id=d.id
        JOIN delivery_steps previous ON previous.delivery_id=d.id AND previous.number=NEW.number-1
        WHERE d.id=NEW.delivery_id AND d.provider_recovery_version=1 AND d.checkpoint_recovery_version=1
          AND NEW.cycle=0 AND p.kind='plan' AND p.number=1 AND p.status='finished'
          AND json_extract(NEW.input,'$.implementation_step_id')=src.implementation_id
          AND json_extract(NEW.input,'$.source_check_id') IS NULL
          AND json_extract(NEW.input,'$.config_hash')=d.config_hash AND json_extract(NEW.input,'$.spec_revision_id')=d.spec_revision_id
          AND ((NEW.kind='checkpoint_snapshot' AND previous.id=p.id
            AND json_extract(NEW.input,'$.source_candidate_commit') IS NULL
            AND #{uuid("json_extract(NEW.input,'$.check_id')")}
            AND json_extract(NEW.input,'$.run_workspace')=json_extract(s.input,'$.workspace'))
          OR (NEW.kind='checkpoint_check' AND previous.kind='checkpoint_snapshot' AND previous.status='finished'
            AND json_extract(NEW.input,'$.snapshot_step_id')=previous.id
            AND json_extract(NEW.input,'$.plan_step_id')=json_extract(previous.input,'$.plan_step_id')
            AND json_extract(NEW.input,'$.workspace')=json_extract(previous.receipt,'$.workspace')
            AND json_extract(NEW.input,'$.candidate_commit')=json_extract(previous.receipt,'$.candidate_commit'))))
    BEGIN SELECT RAISE(ABORT,'provider checkpoint requires retained source and fresh checks'); END
    """)

    execute("""
    CREATE TRIGGER provider_checkpoint_receipt BEFORE UPDATE ON delivery_steps
    WHEN NEW.kind='checkpoint_snapshot' AND NEW.status='finished'
      AND EXISTS (SELECT 1 FROM deliveries WHERE id=NEW.delivery_id AND provider_recovery_version=1)
      AND NOT COALESCE(json_extract(NEW.receipt,'$.workspace.path')!=json_extract(NEW.input,'$.run_workspace.path'),0)
    BEGIN SELECT RAISE(ABORT,'provider capture must preserve its source workspace'); END
    """)
  end

  def down do
    unless repo().query!("SELECT count(*) FROM deliveries WHERE provider_recovery_version=1").rows ==
             [[0]],
           do: raise("Refusing to discard provider recovery history")

    for name <-
          ~w(provider_recovery_immutable provider_recovery_source provider_checkpoint_stage provider_checkpoint_receipt),
        do: execute("DROP TRIGGER #{name}")

    rewrite(false)
    execute("DROP VIEW provider_retry_sources")
    Boss.Repo.Migrations.AddProviderRecoverySchema.down()
  end

  defp provider_sources do
    [[sql]] =
      repo().query!(
        "SELECT sql FROM sqlite_master WHERE type='view' AND name='execution_retry_sources'"
      ).rows

    anchor = ~r/AND s\.cycle=d\.cycle AND [^\n]+/

    unless length(Regex.scan(anchor, sql)) == 1,
      do: raise("Unexpected execution retry source boundary")

    sql =
      sql
      |> String.replace(
        "CREATE VIEW execution_retry_sources AS",
        "CREATE VIEW provider_retry_sources AS"
      )
      |> then(&Regex.replace(anchor, &1, "AND s.cycle=d.cycle AND " <> rate_limit()))

    execute(
      sql <>
        " AND " <>
        implementation_base() <>
        " AND #{sha("json_extract(d.intent,'$.base_commit')")} AND #{sha("json_extract(s.input,'$.workspace.base_commit')")}" <>
        " AND json_type(s.input,'$.workspace')='object' AND json_type(s.input,'$.workspace.path')='text' AND json_type(s.input,'$.workspace.branch')='text'" <>
        " AND ((#{transport("p")} AND json_extract(p.receipt,'$.exit_code')=0) OR (d.execution_recovery_version=1 AND p.number=1 AND json_extract(p.receipt,'$.outcome')='retained_plan' AND json_extract(p.receipt,'$.cleanup')='group_empty'))"
    )
  end

  defp rewrite(up?) do
    changes = [
      {"checkpoint_source", "NEW.checkpoint_recovery_version=1 AND (",
       "NEW.checkpoint_recovery_version=1 AND NEW.provider_recovery_version=0 AND ("},
      {"checkpoint_stage",
       "WHEN NEW.kind IN ('checkpoint_snapshot','checkpoint_check') AND NOT EXISTS (",
       "WHEN NEW.kind IN ('checkpoint_snapshot','checkpoint_check') AND NOT EXISTS (SELECT 1 FROM deliveries WHERE id=NEW.delivery_id AND provider_recovery_version=1) AND NOT EXISTS ("},
      {"retained_retry_sources", "WHERE d.checkpoint_recovery_version=1",
       "WHERE d.checkpoint_recovery_version=1 AND d.provider_recovery_version=0\nUNION ALL\nSELECT d.id,src.parent_id,src.implementation_id,src.plan_id,src.terminal_version FROM deliveries d JOIN provider_retry_sources src ON src.implementation_id=d.retry_implementation_id WHERE d.checkpoint_recovery_version=1 AND d.provider_recovery_version=1"},
      {"checkpoint_retry_sources",
       "AND json_extract(c.input,'$.source_check_id')=d.retry_source_check_id",
       "AND (json_extract(c.input,'$.source_check_id')=d.retry_source_check_id OR (d.provider_recovery_version=1 AND d.retry_source_check_id IS NULL AND json_extract(c.input,'$.source_check_id') IS NULL))"}
    ]

    for {name, old, new} <- if(up?, do: changes, else: Enum.reverse(changes)) do
      flush()

      type =
        if name in ~w(retained_retry_sources checkpoint_retry_sources),
          do: "view",
          else: "trigger"

      [[sql]] =
        repo().query!("SELECT sql FROM sqlite_master WHERE type=? AND name=?", [type, name]).rows

      {from, to} = if up?, do: {old, new}, else: {new, old}

      unless String.contains?(sql, from),
        do: raise("Unexpected #{name} provider recovery boundary")

      execute("DROP #{String.upcase(type)} #{name}")
      execute(String.replace(sql, from, to))
    end

    flush()
  end

  defp rate_limit,
    do:
      "d.failure_code='provider_rate_limit' AND s.kind='implement' AND s.status='failed' AND json_extract(s.receipt,'$.outcome')='exited' AND #{transport("s")} AND json_extract(s.receipt,'$.exit_code') BETWEEN 1 AND 2147483647 AND json_type(s.receipt,'$.signal')='null' AND json_extract(s.receipt,'$.summary.error_class')='rate_limit'"

  defp implementation_base,
    do:
      "((s.cycle=1 AND d.retry_review_id IS NULL AND d.retry_implementation_id IS NULL AND previous.id=p.id AND previous.kind='plan' AND previous.status='finished' AND json_extract(s.input,'$.workspace.base_commit')=json_extract(d.intent,'$.base_commit')) OR (s.cycle=1 AND d.retry_review_id IS NOT NULL AND previous.kind='retry_check' AND json_extract(previous.input,'$.plan_step_id')=p.id AND #{transport("previous")} AND json_type(previous.receipt,'$.output_complete')='true' AND json_extract(previous.receipt,'$.candidate_commit')=json_extract(previous.input,'$.candidate_commit') AND #{hash("json_extract(previous.receipt,'$.output_hash')")} AND json_extract(s.input,'$.workspace.base_commit')=json_extract(previous.input,'$.candidate_commit')) OR (previous.kind='resolve' AND previous.cycle=s.cycle-1 AND previous.status='finished' AND #{transport("previous")} AND json_extract(previous.receipt,'$.exit_code')=0 AND json_type(previous.receipt,'$.report.external_action')='null' AND json_extract(previous.input,'$.plan_step_id')=p.id AND json_extract(s.input,'$.workspace.base_commit')=json_extract(previous.input,'$.candidate_commit')))"

  defp transport(s),
    do:
      "json_extract(#{s}.receipt,'$.cleanup')='group_empty' AND json_extract(#{s}.receipt,'$.exit_kind')='exit' AND json_type(#{s}.receipt,'$.exit_code')='integer' AND json_type(#{s}.receipt,'$.eof')='object' AND (SELECT count(*) FROM json_each(#{s}.receipt,'$.eof'))=2 AND json_type(#{s}.receipt,'$.eof.stdout')='true' AND json_type(#{s}.receipt,'$.eof.stderr')='true'"

  defp uuid(s),
    do:
      "(length(#{s})=36 AND substr(#{s},9,1)='-' AND substr(#{s},14,1)='-' AND substr(#{s},19,1)='-' AND substr(#{s},24,1)='-' AND length(replace(#{s},'-',''))=32 AND replace(#{s},'-','') NOT GLOB '*[^0-9a-fA-F]*')"

  defp sha(s), do: "(length(#{s}) IN (40,64) AND #{s} NOT GLOB '*[^0-9a-f]*')"
  defp hash(s), do: "(length(#{s})=64 AND #{s} NOT GLOB '*[^0-9a-f]*')"
end

defmodule Boss.Repo.Migrations.AddProviderRecoverySchema do
  use Ecto.Migration

  def up,
    do:
      execute(
        "ALTER TABLE deliveries ADD COLUMN provider_recovery_version INTEGER NOT NULL DEFAULT 0 CHECK(provider_recovery_version IN (0,1))"
      )

  def down do
    unless repo().query!("SELECT count(*) FROM deliveries WHERE provider_recovery_version=1").rows ==
             [[0]],
           do: raise("Refusing to discard provider recovery history")

    execute("ALTER TABLE deliveries DROP COLUMN provider_recovery_version")
  end
end
