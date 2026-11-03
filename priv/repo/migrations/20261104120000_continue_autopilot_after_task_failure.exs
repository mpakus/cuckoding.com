defmodule Boss.Repo.Migrations.ContinueAutopilotAfterTaskFailure do
  use Ecto.Migration

  def up do
    replace_guard("""
    AND NOT (d.status IN ('failed','blocked','needs_input')
      AND d.cleanup='group_empty' AND d.integration_command_id IS NULL)
    """)
  end

  def down, do: replace_guard("")

  defp replace_guard(settled) do
    execute("DROP TRIGGER autopilot_delivery_guard")

    execute("""
    CREATE TRIGGER autopilot_delivery_guard BEFORE INSERT ON deliveries
    WHEN (EXISTS (SELECT 1 FROM autopilots WHERE status='running')
      AND NOT EXISTS (SELECT 1 FROM autopilot_items i JOIN autopilots b ON b.id=i.autopilot_id JOIN delivery_requests r ON r.id=i.request_id
        WHERE b.status='running' AND r.task_id=NEW.task_id AND r.command_id=NEW.command_id))
      OR EXISTS (SELECT 1 FROM autopilot_items i JOIN autopilots b ON b.id=i.autopilot_id JOIN delivery_requests r ON r.id=i.request_id
        WHERE r.task_id=NEW.task_id AND r.command_id=NEW.command_id AND (b.status!='running'
          OR (SELECT COUNT(*) FROM autopilot_items WHERE autopilot_id=b.id)!=json_array_length(b.task_ids)
          OR EXISTS (SELECT 1 FROM autopilot_items j JOIN delivery_requests q ON q.id=j.request_id JOIN deliveries d ON d.id=q.delivery_id
            WHERE j.autopilot_id=b.id AND d.status!='done'#{settled})))
    BEGIN SELECT RAISE(ABORT, 'autopilot sequence unavailable'); END
    """)
  end
end
