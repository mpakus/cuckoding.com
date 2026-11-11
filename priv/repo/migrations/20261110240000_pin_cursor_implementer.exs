defmodule Boss.Repo.Migrations.PinCursorImplementer do
  use Ecto.Migration

  def up do
    alter table(:deliveries) do
      add :implementer, :string, null: false, default: "codex"
    end

    execute("""
    CREATE TRIGGER delivery_implementer_check BEFORE INSERT ON deliveries
    WHEN NEW.implementer NOT IN ('codex','cursor')
    BEGIN SELECT RAISE(ABORT, 'unknown implementer'); END
    """)

    execute("""
    CREATE TRIGGER delivery_implementer_immutable BEFORE UPDATE OF implementer ON deliveries
    WHEN NEW.implementer IS NOT OLD.implementer
    BEGIN SELECT RAISE(ABORT, 'delivery implementer is immutable'); END
    """)

    rewrite_model_trigger("delivery_catalog_model")
    rewrite_model_trigger("delivery_model_profile")
  end

  def down do
    execute("DROP TRIGGER IF EXISTS delivery_implementer_immutable")
    execute("DROP TRIGGER IF EXISTS delivery_implementer_check")

    alter table(:deliveries) do
      remove :implementer
    end
  end

  defp rewrite_model_trigger(name) do
    flush()

    [[sql]] =
      repo().query!("SELECT sql FROM sqlite_schema WHERE type='trigger' AND name=?", [name]).rows

    needle = "(d.reviewer!='claude' OR NEW.kind NOT IN ('review','merge_review'))"

    replacement =
      "(d.reviewer NOT IN ('claude','cursor') OR NEW.kind NOT IN ('review','merge_review')) AND (COALESCE(d.implementer,'codex')!='cursor' OR NEW.kind NOT IN ('plan','implement','resolve'))"

    if String.contains?(sql, needle) do
      execute("DROP TRIGGER #{name}")
      execute(String.replace(sql, needle, replacement, global: false))
    else
      raise "Missing #{name} reviewer boundary"
    end
  end
end
