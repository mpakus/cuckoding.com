defmodule Boss.Repo.Migrations.ReleaseUnknownCleanup do
  use Ecto.Migration

  # Keep equality pins on columns that exist from create_deliveries through
  # catalog-routing rollback; do not reference model_catalog/routing_version/roles.
  @old "OR OLD.status IN ('done','blocked','needs_input','failed','cancelled','interrupted')"
  @new """
  OR (OLD.status IN ('done','blocked','needs_input','failed','cancelled','interrupted')
      AND NOT (
        OLD.status='interrupted' AND OLD.cleanup='unknown' AND OLD.autonomy_version=1
        AND NEW.status='blocked' AND NEW.cleanup='group_empty' AND NEW.autonomy_version=1
        AND NEW.id=OLD.id AND NEW.project_id=OLD.project_id AND NEW.task_id=OLD.task_id
        AND NEW.spec_revision_id=OLD.spec_revision_id AND NEW.command_id=OLD.command_id
        AND NEW.admitted_version=OLD.admitted_version AND NEW.check_config=OLD.check_config
        AND NEW.config_hash=OLD.config_hash AND NEW.intent=OLD.intent
        AND NEW.integration_intent=OLD.integration_intent
        AND NEW.integration_command_id IS OLD.integration_command_id
      ))
  """

  def up, do: rewrite("delivery_immutable", @old, String.trim(@new))
  def down, do: rewrite("delivery_immutable", String.trim(@new), @old)

  defp rewrite(name, needle, replacement) do
    flush()

    [[sql]] =
      repo().query!("SELECT sql FROM sqlite_schema WHERE type='trigger' AND name=?", [name]).rows

    unless String.contains?(sql, needle), do: raise("Missing #{name} boundary")

    execute("DROP TRIGGER #{name}")
    execute(String.replace(sql, needle, replacement, global: false))
    flush()
  end
end
