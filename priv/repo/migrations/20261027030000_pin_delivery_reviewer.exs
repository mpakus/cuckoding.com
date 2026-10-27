defmodule Boss.Repo.Migrations.PinDeliveryReviewer do
  use Ecto.Migration

  def up do
    execute("""
    ALTER TABLE deliveries ADD COLUMN reviewer TEXT NOT NULL DEFAULT 'codex'
      CHECK (reviewer IN ('codex','claude'))
    """)

    execute("""
    CREATE TRIGGER delivery_reviewer_immutable BEFORE UPDATE OF reviewer ON deliveries
    WHEN NEW.reviewer IS NOT OLD.reviewer
    BEGIN SELECT RAISE(ABORT, 'delivery reviewer is immutable'); END
    """)
  end

  def down do
    case repo().query!("SELECT COUNT(*) FROM deliveries WHERE reviewer!='codex'").rows do
      [[0]] -> :ok
      _ -> raise "Refusing to discard Claude reviewer history"
    end

    execute("DROP TRIGGER delivery_reviewer_immutable")
    execute("ALTER TABLE deliveries DROP COLUMN reviewer")
  end
end
