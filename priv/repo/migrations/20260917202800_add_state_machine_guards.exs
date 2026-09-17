defmodule Cuckoding.Repo.Migrations.AddStateMachineGuards do
  use Ecto.Migration

  def change do
    alter table(:runs) do
      add :wait_reason, :string,
        check: %{
          name: "run_wait_reason_is_valid",
          expr: "state != 'waiting' OR wait_reason IS NOT NULL"
        }
    end

    immutable(:workflow_versions)
    immutable(:project_config_versions)
  end

  defp immutable(table) do
    execute(
      """
      CREATE TRIGGER #{table}_no_update
      BEFORE UPDATE ON #{table}
      BEGIN
        SELECT RAISE(ABORT, '#{table} are immutable');
      END;
      """,
      "DROP TRIGGER #{table}_no_update"
    )

    execute(
      """
      CREATE TRIGGER #{table}_no_delete
      BEFORE DELETE ON #{table}
      BEGIN
        SELECT RAISE(ABORT, '#{table} are immutable');
      END;
      """,
      "DROP TRIGGER #{table}_no_delete"
    )
  end
end
