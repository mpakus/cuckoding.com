defmodule Cuckoding.Repo.Migrations.CreateCoreDomain do
  use Ecto.Migration

  def change do
    create_projects()
    create_configuration()
    create_work_management()
    create_execution()
  end

  defp create_projects do
    create table(:projects, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :description, :text
      add :repo_path, :text, null: false
      add :default_branch, :string, null: false
      add :workspace_root, :text, null: false
      add :port_range_start, :integer,
        null: false,
        check: %{name: "projects_port_start_is_valid", expr: "port_range_start BETWEEN 1024 AND 65535"}

      add :port_range_end, :integer,
        null: false,
        check: %{
          name: "projects_port_range_is_valid",
          expr: "port_range_end BETWEEN port_range_start AND 65535"
        }

      add :status, :string,
        null: false,
        default: "active",
        check: %{name: "projects_status_is_valid", expr: "status IN ('active', 'archived')"}

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:projects, [:repo_path])
  end

  defp create_configuration do
    create table(:project_config_versions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :project_id, references(:projects, type: :binary_id, on_delete: :restrict), null: false
      add :revision, :integer, null: false
      add :source_hash, :string, null: false
      add :config_json, :map, null: false
      add :trusted_at, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(:project_config_versions, [:project_id, :revision])
    create unique_index(:project_config_versions, [:project_id, :source_hash])

    create table(:workflow_versions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :project_id, references(:projects, type: :binary_id, on_delete: :restrict)
      add :name, :string, null: false
      add :version, :integer, null: false
      add :definition_json, :map, null: false
      add :published_at, :utc_datetime_usec, null: false
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(:workflow_versions, [:project_id, :name, :version],
             where: "project_id IS NOT NULL",
             name: :workflow_versions_project_name_version_index
           )

    create unique_index(:workflow_versions, [:name, :version],
             where: "project_id IS NULL",
             name: :workflow_versions_global_name_version_index
           )

    create table(:provider_accounts, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :adapter_key, :string, null: false
      add :label, :string, null: false
      add :auth_mode, :string, null: false
      add :status, :string, null: false, default: "unknown"
      add :capabilities_json, :map, null: false, default: %{}
      add :probed_at, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:provider_accounts, [:adapter_key, :label])
  end

  defp create_work_management do
    create table(:boards, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :project_id, references(:projects, type: :binary_id, on_delete: :restrict), null: false

      add :workflow_version_id,
          references(:workflow_versions, type: :binary_id, on_delete: :restrict),
          null: false

      add :name, :string, null: false
      add :description, :text
      add :status, :string,
        null: false,
        default: "active",
        check: %{name: "boards_status_is_valid", expr: "status IN ('active', 'paused', 'archived')"}

      add :concurrency_limit, :integer,
        null: false,
        default: 1,
        check: %{name: "boards_concurrency_is_positive", expr: "concurrency_limit > 0"}

      add :unattended_until, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:boards, [:project_id, :name])

    create table(:role_assignments, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :board_id, references(:boards, type: :binary_id, on_delete: :delete_all), null: false
      add :role_key, :string, null: false
      add :role_kind, :string,
        null: false,
        check: %{
          name: "role_kind_is_valid",
          expr:
            "role_kind IN ('agent', 'human', 'system') AND " <>
              "(role_kind != 'system' OR (adapter_key IS NULL AND model_ref IS NULL))"
        }

      add :adapter_key, :string
      add :model_ref, :string
      add :settings_json, :map, null: false, default: %{}
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:role_assignments, [:board_id, :role_key])

    create table(:tasks, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :board_id, references(:boards, type: :binary_id, on_delete: :restrict), null: false
      add :title, :string, null: false
      add :description, :text
      add :priority, :integer, null: false, default: 0
      add :position, :integer,
        null: false,
        check: %{name: "task_position_is_non_negative", expr: "position >= 0"}

      add :state, :string,
        null: false,
        default: "draft",
        check: %{
          name: "task_state_is_valid",
          expr:
            "state IN ('draft', 'ready', 'running', 'waiting', 'paused', 'hibernated', " <>
              "'blocked', 'done', 'failed', 'cancelled', 'archived') AND " <>
              "(state != 'waiting' OR wait_reason IS NOT NULL)"
        }

      add :wait_reason, :string
      add :active_run_id, :binary_id
      timestamps(type: :utc_datetime_usec)
    end

    create index(:tasks, [:board_id, :state, :position])
    create unique_index(:tasks, [:active_run_id], where: "active_run_id IS NOT NULL")

    create table(:task_dependencies, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :task_id, references(:tasks, type: :binary_id, on_delete: :delete_all), null: false

      add :depends_on_task_id, references(:tasks, type: :binary_id, on_delete: :restrict),
        null: false,
        check: %{
          name: "task_dependency_is_not_self",
          expr: "task_id != depends_on_task_id"
        }

      add :kind, :string, null: false, default: "blocks"
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(:task_dependencies, [:task_id, :depends_on_task_id])

    create_runs()
  end

  defp create_runs do
    create table(:runs, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :task_id, references(:tasks, type: :binary_id, on_delete: :restrict), null: false
      add :sequence, :integer,
        null: false,
        check: %{name: "run_sequence_is_positive", expr: "sequence > 0"}

      add :state, :string,
        null: false,
        default: "queued",
        check: %{
          name: "run_state_is_valid",
          expr:
            "state IN ('queued', 'running', 'waiting', 'paused', 'hibernated', 'blocked', " <>
              "'done', 'failed', 'cancelled')"
        }

      add :workflow_snapshot_json, :map, null: false

      add :policy_snapshot_id,
          references(:project_config_versions, type: :binary_id, on_delete: :restrict),
          null: false

      add :plugin_snapshot_json, :map, null: false, default: %{}
      add :branch, :string, null: false
      add :base_sha, :string, null: false
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:runs, [:task_id, :sequence])

    create table(:stage_attempts, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :run_id, references(:runs, type: :binary_id, on_delete: :restrict), null: false
      add :stage_key, :string, null: false
      add :attempt, :integer,
        null: false,
        check: %{name: "stage_attempt_is_positive", expr: "attempt > 0"}

      add :state, :string,
        null: false,
        default: "pending",
        check: %{
          name: "stage_state_is_valid",
          expr: "state IN ('pending', 'running', 'waiting', 'succeeded', 'failed', 'cancelled')"
        }

      add :role_key, :string, null: false
      add :role_kind, :string,
        null: false,
        check: %{name: "stage_role_kind_is_valid", expr: "role_kind IN ('agent', 'human', 'system')"}

      add :started_at, :utc_datetime_usec
      add :finished_at, :utc_datetime_usec
      add :active_ms, :integer,
        null: false,
        default: 0,
        check: %{name: "stage_active_ms_is_non_negative", expr: "active_ms >= 0"}

      add :wall_ms, :integer,
        null: false,
        default: 0,
        check: %{name: "stage_durations_are_valid", expr: "wall_ms >= active_ms"}

      add :checkpoint_json, :map
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:stage_attempts, [:run_id, :stage_key, :attempt])

    create unique_index(:stage_attempts, [:run_id, :stage_key],
             where: "state IN ('pending', 'running', 'waiting')",
             name: :stage_attempts_one_active_index
           )

    create_review_tables()
  end

  defp create_review_tables do
    create table(:approvals, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :run_id, references(:runs, type: :binary_id, on_delete: :restrict), null: false

      add :stage_attempt_id, references(:stage_attempts, type: :binary_id, on_delete: :restrict)
      add :kind, :string, null: false
      add :decision, :string,
        null: false,
        default: "pending",
        check: %{
          name: "approval_decision_is_valid",
          expr: "decision IN ('pending', 'approved', 'rejected')"
        }

      add :actor, :string
      add :reason, :text
      add :decided_at, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec)
    end

    create table(:findings, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :run_id, references(:runs, type: :binary_id, on_delete: :restrict), null: false

      add :stage_attempt_id,
          references(:stage_attempts, type: :binary_id, on_delete: :restrict),
          null: false

      add :severity, :string,
        null: false,
        check: %{
          name: "finding_severity_is_valid",
          expr: "severity IN ('info', 'warning', 'error', 'blocker')"
        }

      add :category, :string, null: false
      add :status, :string,
        null: false,
        default: "open",
        check: %{
          name: "finding_status_is_valid",
          expr: "status IN ('open', 'resolved', 'dismissed')"
        }

      add :summary, :text, null: false
      add :evidence_json, :map, null: false, default: %{}
      timestamps(type: :utc_datetime_usec)
    end

  end

  defp create_execution do
    create table(:environments, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :run_id, references(:runs, type: :binary_id, on_delete: :restrict), null: false
      add :runner_key, :string, null: false
      add :kind, :string,
        null: false,
        check: %{
          name: "environment_kind_is_valid",
          expr: "kind IN ('local_process', 'container', 'remote')"
        }

      add :worktree_path, :text, null: false
      add :run_dir, :text, null: false
      add :base_sha, :string, null: false
      add :head_sha, :string
      add :ports_json, :map, null: false, default: %{}
      add :port, :integer,
        check: %{name: "environment_port_is_valid", expr: "port IS NULL OR port BETWEEN 1024 AND 65535"}

      add :preview_url, :text
      add :isolation_claims_json, :map, null: false, default: %{}
      add :state, :string,
        null: false,
        default: "prepared",
        check: %{
          name: "environment_state_is_valid",
          expr: "state IN ('prepared', 'running', 'hibernated', 'stopped', 'failed')"
        }

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:environments, [:run_id],
             where: "state NOT IN ('stopped', 'failed')",
             name: :environments_one_active_run_index
           )

    create unique_index(:environments, [:port],
             where: "port IS NOT NULL AND state IN ('prepared', 'running')",
             name: :environments_one_active_port_index
           )

    create table(:agent_sessions, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :stage_attempt_id,
          references(:stage_attempts, type: :binary_id, on_delete: :restrict),
          null: false

      add :adapter_key, :string, null: false
      add :runtime_version, :string
      add :requested_model, :string
      add :actual_model, :string
      add :external_session_id, :string
      add :effective_grant_json, :map, null: false, default: %{}
      add :state, :string, null: false, default: "created"
      timestamps(type: :utc_datetime_usec)
    end

    create table(:processes, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :environment_id, references(:environments, type: :binary_id, on_delete: :restrict),
        null: false

      add :agent_session_id, references(:agent_sessions, type: :binary_id, on_delete: :restrict)
      add :command_id, references(:commands, type: :binary_id, on_delete: :restrict)
      add :pid, :integer, null: false
      add :pgid, :integer, null: false
      add :start_identity, :string, null: false
      add :role, :string, null: false
      add :state, :string, null: false, default: "running"
      add :exit_code, :integer
      add :ended_at, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:processes, [:pid, :start_identity])
  end
end
