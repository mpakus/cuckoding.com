defmodule Cuckoding.Repo.Migrations.CheckFeedback do
  use Ecto.Migration

  def up do
    execute """
    CREATE TRIGGER battle_attempt_feedback_shape
    BEFORE UPDATE OF result ON battle_attempts
    WHEN json_type(NEW.result, '$.check_feedback') IS NOT NULL
      AND (NEW.stage NOT IN ('checks','final_checks')
        OR json_type(NEW.result, '$.check_feedback') != 'array'
        OR json_array_length(NEW.result, '$.check_feedback') > 1)
    BEGIN SELECT RAISE(ABORT, 'invalid check feedback shape'); END
    """
  end

  def down, do: raise("forward-only migration; restore a verified backup")
end
