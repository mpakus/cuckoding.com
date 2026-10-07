defmodule Cuckoding.Repo.Migrations.SavedTeam do
  use Ecto.Migration

  def up do
    create table(:team_revisions) do
      add :command_id, references(:commands, type: :binary_id)
      add :definition, :map, null: false
      add :inserted_at, :utc_datetime_usec, null: false
    end

    create unique_index(:team_revisions, [:command_id])

    execute """
    INSERT INTO team_revisions (definition, inserted_at) VALUES
    ('{"version":1,"execution":"disabled","roles":[
      {"id":"speculator","name":"Speculator","instructions":"Write specifications and tasks from the user description and project documents.","agent":"","model_id":"","model":""},
      {"id":"implementor","name":"Implementor","instructions":"Implement the agreed task and verify it with focused tests.","agent":"","model_id":"","model":""},
      {"id":"secutor","name":"Secutor","instructions":"Review the result against the specification. Report completion or return actionable comments to Speculator.","agent":"","model_id":"","model":""},
      {"id":"summa_rudis","name":"Summa Rudis","instructions":"Coordinate the team, track progress and resolve workflow decisions within the recorded user policy.","agent":"","model_id":"","model":""}
    ]}', CURRENT_TIMESTAMP)
    """

    execute "CREATE TRIGGER team_no_update BEFORE UPDATE ON team_revisions BEGIN SELECT RAISE(ABORT, 'append-only team revisions'); END"
    execute "CREATE TRIGGER team_no_delete BEFORE DELETE ON team_revisions BEGIN SELECT RAISE(ABORT, 'append-only team revisions'); END"
  end

  def down, do: raise("forward-only migration; restore a verified backup")
end
