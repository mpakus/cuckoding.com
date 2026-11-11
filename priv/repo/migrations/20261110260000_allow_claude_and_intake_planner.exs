defmodule Boss.Repo.Migrations.AllowClaudeAndIntakePlanner do
  use Ecto.Migration

  def up do
    execute("DROP TRIGGER delivery_implementer_check")

    execute("""
    CREATE TRIGGER delivery_implementer_check BEFORE INSERT ON deliveries
    WHEN NEW.implementer NOT IN ('codex','claude','cursor')
    BEGIN SELECT RAISE(ABORT, 'unknown implementer'); END
    """)

    execute("DROP TRIGGER delivery_analytic_check")

    execute("""
    CREATE TRIGGER delivery_analytic_check BEFORE INSERT ON deliveries
    WHEN NEW.analytic NOT IN ('codex','claude','cursor')
    BEGIN SELECT RAISE(ABORT, 'unknown analytic'); END
    """)

    rewrite("delivery_catalog_model", [
      {
        "(COALESCE(d.implementer,'codex')!='cursor' OR NEW.kind NOT IN ('plan','implement','resolve'))",
        "(COALESCE(d.implementer,'codex') NOT IN ('claude','cursor') OR NEW.kind NOT IN ('plan','implement','resolve'))"
      },
      {
        "(COALESCE(d.analytic,'codex')!='cursor' OR NEW.kind!='resolve')",
        "(COALESCE(d.analytic,'codex') NOT IN ('claude','cursor') OR NEW.kind!='resolve')"
      }
    ])

    rewrite("delivery_model_profile", [
      {
        "(COALESCE(d.implementer,'codex')!='cursor' OR NEW.kind NOT IN ('plan','implement','resolve'))",
        "(COALESCE(d.implementer,'codex') NOT IN ('claude','cursor') OR NEW.kind NOT IN ('plan','implement','resolve'))"
      },
      {
        "(COALESCE(d.analytic,'codex')!='cursor' OR NEW.kind!='resolve')",
        "(COALESCE(d.analytic,'codex') NOT IN ('claude','cursor') OR NEW.kind!='resolve')"
      }
    ])

    rewrite("intake_catalog_required", [
      {
        "AND NEW.model_catalog='{}'",
        "AND NEW.model_catalog='{}' AND NOT EXISTS (SELECT 1 FROM agent_roles ar JOIN agent_role_members arm ON arm.role_id=ar.id WHERE ar.kind='analytic' AND arm.agent_id IN ('claude','cursor'))"
      }
    ])

    rewrite("intake_attempt_insert", [
      {
        "AND r.model_catalog!='{}'",
        "AND (r.model_catalog!='{}' OR json_extract(NEW.model_profile,'$.model') IN ('claude','cursor'))"
      },
      {
        "AND EXISTS (SELECT 1 FROM (\n      SELECT json_extract(r.model_catalog,'$.primary') AS profile, -1 AS priority WHERE NEW.number=1",
        "AND ((r.model_catalog='{}' AND json_extract(NEW.model_profile,'$.model') IN ('claude','cursor') AND json_extract(NEW.model_profile,'$.reasoning_effort')='high') OR EXISTS (SELECT 1 FROM (\n      SELECT json_extract(r.model_catalog,'$.primary') AS profile, -1 AS priority WHERE NEW.number=1"
      },
      {
        "AND json_extract(NEW.model_profile,'$.reasoning_effort')=json_extract(selected.profile,'$.reasoning_effort'))",
        "AND json_extract(NEW.model_profile,'$.reasoning_effort')=json_extract(selected.profile,'$.reasoning_effort')))"
      }
    ])

    rewrite("intake_attempt_update", [
      {
        "'codex_unavailable','candidate_changed'",
        "'codex_unavailable','claude_unavailable','cursor_unavailable','candidate_changed'"
      }
    ])
  end

  def down do
    rewrite("intake_attempt_update", [
      {
        "'codex_unavailable','claude_unavailable','cursor_unavailable','candidate_changed'",
        "'codex_unavailable','candidate_changed'"
      }
    ])

    rewrite("intake_attempt_insert", [
      {
        "AND (r.model_catalog!='{}' OR json_extract(NEW.model_profile,'$.model') IN ('claude','cursor'))",
        "AND r.model_catalog!='{}'"
      },
      {
        "AND ((r.model_catalog='{}' AND json_extract(NEW.model_profile,'$.model') IN ('claude','cursor') AND json_extract(NEW.model_profile,'$.reasoning_effort')='high') OR EXISTS (SELECT 1 FROM (\n      SELECT json_extract(r.model_catalog,'$.primary') AS profile, -1 AS priority WHERE NEW.number=1",
        "AND EXISTS (SELECT 1 FROM (\n      SELECT json_extract(r.model_catalog,'$.primary') AS profile, -1 AS priority WHERE NEW.number=1"
      },
      {
        "AND json_extract(NEW.model_profile,'$.reasoning_effort')=json_extract(selected.profile,'$.reasoning_effort')))",
        "AND json_extract(NEW.model_profile,'$.reasoning_effort')=json_extract(selected.profile,'$.reasoning_effort'))"
      }
    ])

    rewrite("intake_catalog_required", [
      {
        "AND NEW.model_catalog='{}' AND NOT EXISTS (SELECT 1 FROM agent_roles ar JOIN agent_role_members arm ON arm.role_id=ar.id WHERE ar.kind='analytic' AND arm.agent_id IN ('claude','cursor'))",
        "AND NEW.model_catalog='{}'"
      }
    ])

    rewrite("delivery_model_profile", [
      {
        "(COALESCE(d.implementer,'codex') NOT IN ('claude','cursor') OR NEW.kind NOT IN ('plan','implement','resolve'))",
        "(COALESCE(d.implementer,'codex')!='cursor' OR NEW.kind NOT IN ('plan','implement','resolve'))"
      },
      {
        "(COALESCE(d.analytic,'codex') NOT IN ('claude','cursor') OR NEW.kind!='resolve')",
        "(COALESCE(d.analytic,'codex')!='cursor' OR NEW.kind!='resolve')"
      }
    ])

    rewrite("delivery_catalog_model", [
      {
        "(COALESCE(d.implementer,'codex') NOT IN ('claude','cursor') OR NEW.kind NOT IN ('plan','implement','resolve'))",
        "(COALESCE(d.implementer,'codex')!='cursor' OR NEW.kind NOT IN ('plan','implement','resolve'))"
      },
      {
        "(COALESCE(d.analytic,'codex') NOT IN ('claude','cursor') OR NEW.kind!='resolve')",
        "(COALESCE(d.analytic,'codex')!='cursor' OR NEW.kind!='resolve')"
      }
    ])
  end

  defp rewrite(name, pairs) do
    flush()

    [[sql]] =
      repo().query!("SELECT sql FROM sqlite_schema WHERE type='trigger' AND name=?", [name]).rows

    revised =
      Enum.reduce(pairs, sql, fn {needle, replacement}, current ->
        if String.contains?(current, needle),
          do: String.replace(current, needle, replacement, global: false),
          else: raise("Missing #{name} boundary: #{needle}")
      end)

    execute("DROP TRIGGER #{name}")
    execute(revised)
    flush()
  end
end
