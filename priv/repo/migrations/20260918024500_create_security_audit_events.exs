defmodule Cuckoding.Repo.Migrations.CreateSecurityAuditEvents do
  use Ecto.Migration

  def change do
    create table(:security_audit_events, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :event_type, :string, null: false
      add :method, :string, null: false
      add :path, :string, null: false
      add :status, :integer,
        null: false,
        check: %{name: "security_audit_status_is_rejection", expr: "status IN (401, 403)"}

      add :occurred_at, :utc_datetime_usec, null: false
    end

    create index(:security_audit_events, [:event_type, :occurred_at])

    execute(
      """
      CREATE TRIGGER security_audit_events_no_update
      BEFORE UPDATE ON security_audit_events
      BEGIN
        SELECT RAISE(ABORT, 'security_audit_events are append-only');
      END;
      """,
      "DROP TRIGGER security_audit_events_no_update"
    )

    execute(
      """
      CREATE TRIGGER security_audit_events_no_delete
      BEFORE DELETE ON security_audit_events
      BEGIN
        SELECT RAISE(ABORT, 'security_audit_events are append-only');
      END;
      """,
      "DROP TRIGGER security_audit_events_no_delete"
    )
  end
end
