defmodule Cuckoding.Repo.Migrations.AddPreparedGoals do
  use Ecto.Migration

  def up do
    alter table(:board_executions) do
      add :preparation_json, :map, null: false, default: %{}
      add :delivery_authorization_json, :map
    end

    execute("""
    CREATE TRIGGER board_delivery_authorization_immutable
    BEFORE UPDATE OF delivery_authorization_json ON board_executions
    WHEN OLD.delivery_authorization_json IS NOT NULL
    AND NEW.delivery_authorization_json IS NOT OLD.delivery_authorization_json
    BEGIN SELECT RAISE(ABORT, 'delivery authorization is immutable'); END
    """)
  end

  def down, do: raise("released migrations are forward-only")
end
