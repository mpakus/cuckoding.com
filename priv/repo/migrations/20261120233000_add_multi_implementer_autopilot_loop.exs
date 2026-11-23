defmodule Boss.Repo.Migrations.AddMultiImplementerAutopilotLoop do
  use Ecto.Migration

  @old_clause "WHERE j.autopilot_id=b.id AND d.status!='done'"
  @new_clause "WHERE j.autopilot_id=b.id AND NOT (EXISTS (SELECT 1 FROM sqlite_schema WHERE type='table' AND name='autopilot_loop_configs') AND EXISTS (SELECT 1 FROM autopilot_loop_configs lc WHERE lc.autopilot_id=b.id AND lc.parallel_enabled=1) AND d.status IN ('planning','implementing','testing','reviewing','ready_to_merge')) AND d.status!='done'"

  def up do
    create table(:project_implementer_pool) do
      add :project_id, references(:projects, on_delete: :delete_all), null: false
      add :member_id, references(:agent_role_members, on_delete: :delete_all)
      add :agent_id, :text, null: false
      add :model_id, :text
      add :reasoning_effort, :text
      add :binding_tag, :text, null: false
      add :position, :integer, null: false, default: 0
      timestamps(type: :utc_datetime_usec)
    end

    create index(:project_implementer_pool, [:project_id, :position])

    execute("""
    CREATE UNIQUE INDEX project_implementer_pool_binding_index
    ON project_implementer_pool (
      project_id,
      agent_id,
      COALESCE(model_id, '__default__'),
      COALESCE(reasoning_effort, 'default')
    )
    """)

    create table(:delivery_implementer_bindings, primary_key: false) do
      add :delivery_id, references(:deliveries, type: :string, on_delete: :restrict),
        primary_key: true

      add :project_id, references(:projects, on_delete: :delete_all), null: false
      add :task_id, references(:tasks, on_delete: :delete_all), null: false
      add :member_id, :integer
      add :agent_id, :text, null: false
      add :model_id, :text
      add :reasoning_effort, :text
      add :binding_tag, :text, null: false
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:delivery_implementer_bindings, [:project_id])
    create index(:delivery_implementer_bindings, [:task_id])

    create table(:autopilot_loop_configs, primary_key: false) do
      add :autopilot_id, references(:autopilots, type: :string, on_delete: :restrict),
        primary_key: true

      add :project_id, references(:projects, on_delete: :delete_all), null: false
      add :parallel_enabled, :integer, null: false, default: 1
      add :spec_loop_enabled, :integer, null: false, default: 1
      add :loop_pass, :integer, null: false, default: 1
      add :max_passes, :integer, null: false, default: 2
      add :parent_autopilot_id, :text
      add :reworked_task_ids, :text, null: false, default: "[]"
      add :next_autopilot_id, :text
      timestamps(type: :utc_datetime_usec)
    end

    create index(:autopilot_loop_configs, [:project_id])

    flush()
    rewrite_guard(@old_clause, @new_clause)
  end

  def down do
    flush()
    rewrite_guard(@new_clause, @old_clause)

    drop_if_exists table(:autopilot_loop_configs)
    drop_if_exists table(:delivery_implementer_bindings)
    execute("DROP INDEX IF EXISTS project_implementer_pool_binding_index")
    drop_if_exists table(:project_implementer_pool)
  end

  defp rewrite_guard(from_sql, to_sql) do
    case repo().query(
           "SELECT sql FROM sqlite_schema WHERE type='trigger' AND name='autopilot_delivery_guard'"
         ) do
      {:ok, %{rows: [[sql]]}} when is_binary(sql) ->
        if String.contains?(sql, from_sql) do
          execute("DROP TRIGGER autopilot_delivery_guard")
          execute(String.replace(sql, from_sql, to_sql))
          flush()
        end

      _ ->
        :ok
    end
  end
end
