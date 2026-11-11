defmodule Boss.Repo.Migrations.PinCursorAnalytic do
  use Ecto.Migration

  def up do
    alter table(:deliveries) do
      add :analytic, :string, null: false, default: "codex"
    end

    execute("""
    CREATE TRIGGER delivery_analytic_check BEFORE INSERT ON deliveries
    WHEN NEW.analytic NOT IN ('codex','cursor')
    BEGIN SELECT RAISE(ABORT, 'unknown analytic'); END
    """)

    execute("""
    CREATE TRIGGER delivery_analytic_immutable BEFORE UPDATE OF analytic ON deliveries
    WHEN NEW.analytic IS NOT OLD.analytic
    BEGIN SELECT RAISE(ABORT, 'delivery analytic is immutable'); END
    """)

    rewrite_model_trigger("delivery_catalog_model")
    rewrite_model_trigger("delivery_model_profile")
  end

  def down do
    rewrite_model_trigger("delivery_catalog_model", :down)
    rewrite_model_trigger("delivery_model_profile", :down)
    execute("DROP TRIGGER IF EXISTS delivery_analytic_immutable")
    execute("DROP TRIGGER IF EXISTS delivery_analytic_check")

    alter table(:deliveries) do
      remove :analytic
    end
  end

  defp rewrite_model_trigger(name, direction \\ :up) do
    flush()

    [[sql]] =
      repo().query!("SELECT sql FROM sqlite_schema WHERE type='trigger' AND name=?", [name]).rows

    {needle, replacement} =
      if direction == :up do
        {
          "(COALESCE(d.implementer,'codex')!='cursor' OR NEW.kind NOT IN ('plan','implement','resolve'))",
          "(COALESCE(d.implementer,'codex')!='cursor' OR NEW.kind NOT IN ('plan','implement','resolve')) AND (COALESCE(d.analytic,'codex')!='cursor' OR NEW.kind!='resolve')"
        }
      else
        {
          " AND (COALESCE(d.analytic,'codex')!='cursor' OR NEW.kind!='resolve')",
          ""
        }
      end

    if String.contains?(sql, needle) do
      execute("DROP TRIGGER #{name}")
      execute(String.replace(sql, needle, replacement, global: false))
    else
      raise "Missing #{name} analytic boundary"
    end
  end
end
