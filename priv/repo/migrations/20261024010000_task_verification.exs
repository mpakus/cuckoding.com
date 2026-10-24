defmodule Cuckoding.Repo.Migrations.TaskVerification do
  use Ecto.Migration

  def up do
    # The forward-only version also fences bundles that cannot retain task checks.
    execute """
    CREATE TRIGGER draft_task_verification_shape
    BEFORE INSERT ON draft_task_revisions
    WHEN json_type(NEW.content, '$.verification') IS NOT NULL
      AND (json_type(NEW.content, '$.verification') != 'array'
        OR json_array_length(NEW.content, '$.verification') > 4)
    BEGIN SELECT RAISE(ABORT, 'invalid task verification shape'); END
    """
  end

  def down, do: raise("forward-only migration; restore a verified backup")
end
