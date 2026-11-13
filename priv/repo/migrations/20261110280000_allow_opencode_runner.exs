defmodule Boss.Repo.Migrations.AllowOpenCodeRunner do
  use Ecto.Migration

  def up do
    rewrite("delivery_request_pin", [
      {"NOT IN ('codex','claude','cursor')", "NOT IN ('codex','claude','cursor','opencode')"}
    ])

    rewrite("autopilot_insert", [
      {"NOT IN ('codex','claude','cursor')", "NOT IN ('codex','claude','cursor','opencode')"}
    ])

    replace_delivery_check(
      "reviewer IN ('codex','claude','cursor')",
      "reviewer IN ('codex','claude','cursor','opencode')"
    )

    execute("DROP TRIGGER delivery_implementer_check")

    execute("""
    CREATE TRIGGER delivery_implementer_check BEFORE INSERT ON deliveries
    WHEN NEW.implementer NOT IN ('codex','claude','cursor','opencode')
    BEGIN SELECT RAISE(ABORT, 'unknown implementer'); END
    """)

    execute("DROP TRIGGER delivery_analytic_check")

    execute("""
    CREATE TRIGGER delivery_analytic_check BEFORE INSERT ON deliveries
    WHEN NEW.analytic NOT IN ('codex','claude','cursor','opencode')
    BEGIN SELECT RAISE(ABORT, 'unknown analytic'); END
    """)

    for trigger <- ["delivery_catalog_model", "delivery_model_profile"] do
      rewrite(trigger, [
        {"d.reviewer NOT IN ('claude','cursor')",
         "d.reviewer NOT IN ('claude','cursor','opencode')"},
        {
          "COALESCE(d.implementer,'codex') NOT IN ('claude','cursor')",
          "COALESCE(d.implementer,'codex') NOT IN ('claude','cursor','opencode')"
        },
        {
          "COALESCE(d.analytic,'codex') NOT IN ('claude','cursor')",
          "COALESCE(d.analytic,'codex') NOT IN ('claude','cursor','opencode')"
        }
      ])
    end

    rewrite("intake_catalog_required", [
      {
        "arm.agent_id IN ('claude','cursor')",
        "arm.agent_id IN ('claude','cursor','opencode')"
      }
    ])

    rewrite("intake_attempt_insert", [
      {
        "json_extract(NEW.model_profile,'$.model') IN ('claude','cursor')",
        "json_extract(NEW.model_profile,'$.model') IN ('claude','cursor','opencode')"
      },
      {
        "json_extract(NEW.model_profile,'$.model') IN ('claude','cursor')",
        "json_extract(NEW.model_profile,'$.model') IN ('claude','cursor','opencode')"
      }
    ])

    rewrite("intake_attempt_update", [
      {
        "'codex_unavailable','claude_unavailable','cursor_unavailable','candidate_changed'",
        "'codex_unavailable','claude_unavailable','cursor_unavailable','opencode_unavailable','candidate_changed'"
      }
    ])
  end

  def down do
    flush()

    case repo().query!(
           "SELECT COUNT(*) FROM deliveries WHERE reviewer='opencode' OR implementer='opencode' OR analytic='opencode'"
         ).rows do
      [[0]] -> :ok
      _ -> raise "Refusing to discard OpenCode delivery history"
    end

    rewrite("intake_attempt_update", [
      {
        "'codex_unavailable','claude_unavailable','cursor_unavailable','opencode_unavailable','candidate_changed'",
        "'codex_unavailable','claude_unavailable','cursor_unavailable','candidate_changed'"
      }
    ])

    rewrite("intake_attempt_insert", [
      {
        "json_extract(NEW.model_profile,'$.model') IN ('claude','cursor','opencode')",
        "json_extract(NEW.model_profile,'$.model') IN ('claude','cursor')"
      },
      {
        "json_extract(NEW.model_profile,'$.model') IN ('claude','cursor','opencode')",
        "json_extract(NEW.model_profile,'$.model') IN ('claude','cursor')"
      }
    ])

    rewrite("intake_catalog_required", [
      {
        "arm.agent_id IN ('claude','cursor','opencode')",
        "arm.agent_id IN ('claude','cursor')"
      }
    ])

    for trigger <- ["delivery_model_profile", "delivery_catalog_model"] do
      rewrite(trigger, [
        {"d.reviewer NOT IN ('claude','cursor','opencode')",
         "d.reviewer NOT IN ('claude','cursor')"},
        {
          "COALESCE(d.implementer,'codex') NOT IN ('claude','cursor','opencode')",
          "COALESCE(d.implementer,'codex') NOT IN ('claude','cursor')"
        },
        {
          "COALESCE(d.analytic,'codex') NOT IN ('claude','cursor','opencode')",
          "COALESCE(d.analytic,'codex') NOT IN ('claude','cursor')"
        }
      ])
    end

    execute("DROP TRIGGER delivery_analytic_check")

    execute("""
    CREATE TRIGGER delivery_analytic_check BEFORE INSERT ON deliveries
    WHEN NEW.analytic NOT IN ('codex','claude','cursor')
    BEGIN SELECT RAISE(ABORT, 'unknown analytic'); END
    """)

    execute("DROP TRIGGER delivery_implementer_check")

    execute("""
    CREATE TRIGGER delivery_implementer_check BEFORE INSERT ON deliveries
    WHEN NEW.implementer NOT IN ('codex','claude','cursor')
    BEGIN SELECT RAISE(ABORT, 'unknown implementer'); END
    """)

    replace_delivery_check(
      "reviewer IN ('codex','claude','cursor','opencode')",
      "reviewer IN ('codex','claude','cursor')"
    )

    rewrite("autopilot_insert", [
      {"NOT IN ('codex','claude','cursor','opencode')", "NOT IN ('codex','claude','cursor')"}
    ])

    rewrite("delivery_request_pin", [
      {"NOT IN ('codex','claude','cursor','opencode')", "NOT IN ('codex','claude','cursor')"}
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

  defp replace_delivery_check(needle, replacement) do
    flush()
    database = repo()

    [[sql]] =
      database.query!("SELECT sql FROM sqlite_schema WHERE type='table' AND name='deliveries'").rows

    unless String.contains?(sql, needle), do: raise("Missing deliveries reviewer check")
    revised = String.replace(sql, needle, replacement, global: false)
    database.query!("PRAGMA writable_schema=ON")

    database.query!("UPDATE sqlite_schema SET sql=? WHERE type='table' AND name='deliveries'", [
      revised
    ])

    database.query!("PRAGMA writable_schema=RESET")

    [[current]] =
      database.query!("SELECT sql FROM sqlite_schema WHERE type='table' AND name='deliveries'").rows

    unless String.contains?(current, replacement), do: raise("Reviewer check was not updated")
  end
end
