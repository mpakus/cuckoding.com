defmodule Cuckoding.Repo.Migrations.TaskBlockAdmission do
  use Ecto.Migration

  def up do
    # Also makes older bundles refuse the new running-with-blocked-lanes policy at startup.
    execute """
    CREATE TRIGGER battle_attempts_blocked_task
    BEFORE INSERT ON battle_attempts
    WHEN NEW.state = 'running' AND NEW.task_id IS NOT NULL AND EXISTS (
      SELECT 1 FROM battles b JOIN battle_tasks t ON t.battle_id = b.id
      WHERE b.id = NEW.battle_id AND t.task_id = NEW.task_id
        AND json_extract(b.snapshot, '$.blocker_scope') = 'task-local-continuation-v1'
        AND t.state = 'needs_attention'
    )
    BEGIN SELECT RAISE(ABORT, 'blocked task cannot be claimed'); END
    """
  end

  def down, do: raise("forward-only migration; restore a verified backup")
end
