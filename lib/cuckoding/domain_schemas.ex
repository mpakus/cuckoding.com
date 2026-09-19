defmodule Cuckoding.Projects.Project do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset
  @primary_key {:id, :binary_id, autogenerate: false}
  schema "projects" do
    field :name, :string
    field :description, :string
    field :repo_path, :string
    field :default_branch, :string
    field :workspace_root, :string
    field :port_range_start, :integer
    field :port_range_end, :integer
    field :status, :string, default: "active"
    timestamps(type: :utc_datetime_usec)
  end

  def create_changeset(record, attrs) do
    record
    |> cast(attrs, [
      :id,
      :name,
      :description,
      :repo_path,
      :default_branch,
      :workspace_root,
      :port_range_start,
      :port_range_end
    ])
    |> validate_required([
      :id,
      :name,
      :repo_path,
      :default_branch,
      :workspace_root,
      :port_range_start,
      :port_range_end
    ])
    |> validate_number(:port_range_start,
      greater_than_or_equal_to: 1_024,
      less_than_or_equal_to: 65_535
    )
    |> validate_number(:port_range_end,
      greater_than_or_equal_to: 1_024,
      less_than_or_equal_to: 65_535
    )
    |> validate_port_range()
    |> unique_constraint(:repo_path)
  end

  defp validate_port_range(changeset) do
    start_port = get_field(changeset, :port_range_start)
    end_port = get_field(changeset, :port_range_end)

    if is_integer(start_port) and is_integer(end_port) and end_port < start_port,
      do: add_error(changeset, :port_range_end, "must not precede the start port"),
      else: changeset
  end
end

defmodule Cuckoding.Projects.ProjectConfigVersion do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset
  @primary_key {:id, :binary_id, autogenerate: false}
  schema "project_config_versions" do
    field :project_id, :binary_id
    field :revision, :integer
    field :source_hash, :string
    field :config_json, :map
    field :trusted_at, :utc_datetime_usec
    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def create_changeset(record, attrs) do
    record
    |> cast(attrs, [:id, :project_id, :revision, :source_hash, :config_json, :trusted_at])
    |> validate_required([:id, :project_id, :revision, :source_hash, :config_json])
    |> validate_number(:revision, greater_than: 0)
    |> foreign_key_constraint(:project_id)
    |> unique_constraint([:project_id, :revision])
    |> unique_constraint([:project_id, :source_hash])
  end
end

defmodule Cuckoding.Workflows.WorkflowVersion do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset
  @primary_key {:id, :binary_id, autogenerate: false}
  schema "workflow_versions" do
    field :project_id, :binary_id
    field :name, :string
    field :version, :integer
    field :definition_json, :map
    field :published_at, :utc_datetime_usec
    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def create_changeset(record, attrs) do
    record
    |> cast(attrs, [:id, :project_id, :name, :version, :definition_json, :published_at])
    |> validate_required([:id, :name, :version, :definition_json, :published_at])
    |> validate_number(:version, greater_than: 0)
    |> foreign_key_constraint(:project_id)
    |> unique_constraint([:project_id, :name, :version],
      name: :workflow_versions_project_name_version_index
    )
    |> unique_constraint([:name, :version], name: :workflow_versions_global_name_version_index)
  end
end

defmodule Cuckoding.Workflows.Board do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset
  @primary_key {:id, :binary_id, autogenerate: false}
  schema "boards" do
    field :project_id, :binary_id
    field :workflow_version_id, :binary_id
    field :name, :string
    field :description, :string
    field :status, :string, default: "active"
    field :concurrency_limit, :integer, default: 1
    field :unattended_until, :utc_datetime_usec
    timestamps(type: :utc_datetime_usec)
  end

  def create_changeset(record, attrs) do
    record
    |> cast(attrs, [
      :id,
      :project_id,
      :workflow_version_id,
      :name,
      :description,
      :concurrency_limit,
      :unattended_until
    ])
    |> validate_required([:id, :project_id, :workflow_version_id, :name, :concurrency_limit])
    |> validate_number(:concurrency_limit, greater_than: 0)
    |> foreign_key_constraint(:project_id)
    |> foreign_key_constraint(:workflow_version_id)
    |> unique_constraint([:project_id, :name])
  end

  def unattended_changeset(record, attrs) do
    record
    |> cast(attrs, [:unattended_until])
  end

  def status_changeset(record, attrs) do
    record
    |> cast(attrs, [:status])
    |> validate_required([:status])
    |> validate_inclusion(:status, ~w(active paused archived))
  end
end

defmodule Cuckoding.Workflows.RoleAssignment do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset
  @primary_key {:id, :binary_id, autogenerate: false}
  schema "role_assignments" do
    field :board_id, :binary_id
    field :role_key, :string
    field :role_kind, :string
    field :adapter_key, :string
    field :model_ref, :string
    field :settings_json, :map, default: %{}
    timestamps(type: :utc_datetime_usec)
  end

  def create_changeset(record, attrs) do
    record
    |> cast(attrs, [
      :id,
      :board_id,
      :role_key,
      :role_kind,
      :adapter_key,
      :model_ref,
      :settings_json
    ])
    |> validate_required([:id, :board_id, :role_key, :role_kind, :settings_json])
    |> validate_inclusion(:role_kind, ~w(agent human system))
    |> validate_system_role()
    |> foreign_key_constraint(:board_id)
    |> unique_constraint([:board_id, :role_key])
  end

  defp validate_system_role(changeset) do
    if get_field(changeset, :role_kind) == "system" and
         (get_field(changeset, :adapter_key) || get_field(changeset, :model_ref)),
       do: add_error(changeset, :role_kind, "system roles cannot select an adapter or model"),
       else: changeset
  end
end

defmodule Cuckoding.Workflows.Task do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset
  @states ~w(draft ready running waiting paused hibernated blocked done failed cancelled archived)
  @primary_key {:id, :binary_id, autogenerate: false}
  schema "tasks" do
    field :board_id, :binary_id
    field :title, :string
    field :description, :string
    field :priority, :integer, default: 0
    field :position, :integer
    field :kind, :string, default: "delivery"
    field :intake_role_key, :string
    field :state, :string, default: "draft"
    field :wait_reason, :string
    field :active_run_id, :binary_id
    timestamps(type: :utc_datetime_usec)
  end

  def create_changeset(record, attrs) do
    record
    |> cast(attrs, [
      :id,
      :board_id,
      :title,
      :description,
      :priority,
      :position,
      :kind,
      :intake_role_key
    ])
    |> validate_required([:id, :board_id, :title, :priority, :position, :kind])
    |> validate_inclusion(:kind, ~w(delivery board_intake))
    |> validate_number(:position, greater_than_or_equal_to: 0)
    |> validate_intake_role()
    |> foreign_key_constraint(:board_id)
  end

  def edit_changeset(record, attrs) do
    record
    |> cast(attrs, [:title, :description, :priority])
    |> validate_required([:title, :priority])
  end

  @doc false
  def transition_changeset(record, attrs) do
    record
    |> cast(attrs, [:state, :wait_reason, :active_run_id])
    |> validate_required([:state])
    |> validate_inclusion(:state, @states)
    |> validate_wait_reason()
    |> unique_constraint(:active_run_id)
  end

  defp validate_wait_reason(changeset) do
    if get_field(changeset, :state) == "waiting" and blank?(get_field(changeset, :wait_reason)),
      do: add_error(changeset, :wait_reason, "is required while waiting"),
      else: changeset
  end

  defp validate_intake_role(changeset) do
    if get_field(changeset, :kind) == "board_intake" and
         blank?(get_field(changeset, :intake_role_key)),
       do: add_error(changeset, :intake_role_key, "is required for a board intake"),
       else: changeset
  end

  defp blank?(value), do: not is_binary(value) or String.trim(value) == ""
end

defmodule Cuckoding.Workflows.TaskProposal do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset
  @primary_key {:id, :binary_id, autogenerate: false}

  schema "task_proposals" do
    field :intake_task_id, :binary_id
    field :position, :integer
    field :title, :string
    field :description, :string
    field :priority, :integer, default: 0
    field :source_json, :map, default: %{}
    field :imported_task_id, :binary_id
    timestamps(type: :utc_datetime_usec)
  end

  def create_changeset(record, attrs) do
    record
    |> cast(attrs, [
      :id,
      :intake_task_id,
      :position,
      :title,
      :description,
      :priority,
      :source_json
    ])
    |> validate_required([:id, :intake_task_id, :position, :title, :priority, :source_json])
    |> validate_length(:title, min: 1, max: 200)
    |> validate_length(:description, max: 10_000)
    |> validate_number(:position, greater_than_or_equal_to: 0)
    |> validate_number(:priority, greater_than_or_equal_to: -100, less_than_or_equal_to: 100)
    |> foreign_key_constraint(:intake_task_id)
    |> unique_constraint([:intake_task_id, :position])
  end

  def import_changeset(record, task_id) do
    record
    |> cast(%{imported_task_id: task_id}, [:imported_task_id])
    |> validate_required([:imported_task_id])
    |> foreign_key_constraint(:imported_task_id)
    |> unique_constraint(:imported_task_id)
  end
end

defmodule Cuckoding.Workflows.TaskDependency do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset
  @primary_key {:id, :binary_id, autogenerate: false}
  schema "task_dependencies" do
    field :task_id, :binary_id
    field :depends_on_task_id, :binary_id
    field :kind, :string, default: "blocks"
    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def create_changeset(record, attrs) do
    record
    |> cast(attrs, [:id, :task_id, :depends_on_task_id, :kind])
    |> validate_required([:id, :task_id, :depends_on_task_id, :kind])
    |> foreign_key_constraint(:task_id)
    |> foreign_key_constraint(:depends_on_task_id)
    |> unique_constraint([:task_id, :depends_on_task_id])
  end
end

defmodule Cuckoding.Execution.Run do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset
  @states ~w(queued running waiting paused hibernated blocked done failed cancelled)
  @primary_key {:id, :binary_id, autogenerate: false}
  schema "runs" do
    field :task_id, :binary_id
    field :sequence, :integer
    field :state, :string, default: "queued"
    field :wait_reason, :string
    field :workflow_snapshot_json, :map
    field :policy_snapshot_id, :binary_id
    field :plugin_snapshot_json, :map, default: %{}
    field :branch, :string
    field :base_sha, :string
    timestamps(type: :utc_datetime_usec)
  end

  def create_changeset(record, attrs) do
    record
    |> cast(attrs, [
      :id,
      :task_id,
      :sequence,
      :workflow_snapshot_json,
      :policy_snapshot_id,
      :plugin_snapshot_json,
      :branch,
      :base_sha
    ])
    |> validate_required([
      :id,
      :task_id,
      :sequence,
      :workflow_snapshot_json,
      :policy_snapshot_id,
      :plugin_snapshot_json,
      :branch,
      :base_sha
    ])
    |> validate_number(:sequence, greater_than: 0)
    |> foreign_key_constraint(:task_id)
    |> foreign_key_constraint(:policy_snapshot_id)
    |> unique_constraint([:task_id, :sequence])
  end

  @doc false
  def transition_changeset(record, attrs) do
    record
    |> cast(attrs, [:state, :wait_reason])
    |> validate_required([:state])
    |> validate_inclusion(:state, @states)
    |> validate_wait_reason()
  end

  defp validate_wait_reason(changeset) do
    if get_field(changeset, :state) == "waiting" and blank?(get_field(changeset, :wait_reason)),
      do: add_error(changeset, :wait_reason, "is required while waiting"),
      else: changeset
  end

  defp blank?(value), do: not is_binary(value) or String.trim(value) == ""
end

defmodule Cuckoding.Execution.StageAttempt do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset
  @primary_key {:id, :binary_id, autogenerate: false}
  schema "stage_attempts" do
    field :run_id, :binary_id
    field :stage_key, :string
    field :attempt, :integer
    field :state, :string, default: "pending"
    field :role_key, :string
    field :role_kind, :string
    field :started_at, :utc_datetime_usec
    field :finished_at, :utc_datetime_usec
    field :active_ms, :integer, default: 0
    field :wall_ms, :integer, default: 0
    field :checkpoint_json, :map
    timestamps(type: :utc_datetime_usec)
  end

  def create_changeset(record, attrs) do
    record
    |> cast(attrs, [:id, :run_id, :stage_key, :attempt, :role_key, :role_kind])
    |> validate_required([:id, :run_id, :stage_key, :attempt, :role_key, :role_kind])
    |> validate_number(:attempt, greater_than: 0)
    |> validate_inclusion(:role_kind, ~w(agent human system))
    |> foreign_key_constraint(:run_id)
    |> unique_constraint([:run_id, :stage_key, :attempt])
    |> unique_constraint([:run_id, :stage_key], name: :stage_attempts_one_active_index)
    |> unique_constraint([:run_id, :stage_key], name: :stage_attempts_run_id_stage_key_index)
  end

  @doc false
  def timing_changeset(record, attrs) do
    record
    |> cast(attrs, [:active_ms, :wall_ms])
    |> validate_required([:active_ms, :wall_ms])
    |> validate_number(:active_ms, greater_than_or_equal_to: 0)
    |> validate_number(:wall_ms, greater_than_or_equal_to: 0)
    |> validate_wall_time()
  end

  def checkpoint_changeset(record, attrs) do
    record
    |> cast(attrs, [:checkpoint_json])
    |> validate_required([:checkpoint_json])
  end

  @doc false
  def transition_changeset(record, attrs) do
    record
    |> cast(attrs, [:state, :started_at, :finished_at])
    |> validate_required([:state])
    |> validate_inclusion(:state, ~w(pending running waiting succeeded failed cancelled))
  end

  defp validate_wall_time(changeset) do
    active_ms = get_field(changeset, :active_ms)
    wall_ms = get_field(changeset, :wall_ms)

    if is_integer(active_ms) and is_integer(wall_ms) and wall_ms < active_ms,
      do: add_error(changeset, :wall_ms, "must include active time"),
      else: changeset
  end
end

defmodule Cuckoding.Workflows.Approval do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset
  @primary_key {:id, :binary_id, autogenerate: false}
  schema "approvals" do
    field :run_id, :binary_id
    field :stage_attempt_id, :binary_id
    field :kind, :string
    field :decision, :string, default: "pending"
    field :actor, :string
    field :reason, :string
    field :decided_at, :utc_datetime_usec
    timestamps(type: :utc_datetime_usec)
  end

  def create_changeset(record, attrs) do
    record
    |> cast(attrs, [:id, :run_id, :stage_attempt_id, :kind])
    |> validate_required([:id, :run_id, :kind])
    |> foreign_key_constraint(:run_id)
    |> foreign_key_constraint(:stage_attempt_id)
  end

  def decision_changeset(record, attrs) do
    record
    |> cast(attrs, [:decision, :actor, :reason, :decided_at])
    |> validate_required([:decision, :actor, :reason, :decided_at])
    |> validate_inclusion(:decision, ~w(approved rejected))
  end
end

defmodule Cuckoding.Workflows.Finding do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset
  @primary_key {:id, :binary_id, autogenerate: false}
  schema "findings" do
    field :run_id, :binary_id
    field :stage_attempt_id, :binary_id
    field :severity, :string
    field :category, :string
    field :status, :string, default: "open"
    field :summary, :string
    field :evidence_json, :map, default: %{}
    timestamps(type: :utc_datetime_usec)
  end

  def create_changeset(record, attrs) do
    record
    |> cast(attrs, [
      :id,
      :run_id,
      :stage_attempt_id,
      :severity,
      :category,
      :summary,
      :evidence_json
    ])
    |> validate_required([
      :id,
      :run_id,
      :stage_attempt_id,
      :severity,
      :category,
      :summary,
      :evidence_json
    ])
    |> validate_inclusion(:severity, ~w(info warning error blocker))
    |> foreign_key_constraint(:run_id)
    |> foreign_key_constraint(:stage_attempt_id)
  end
end

defmodule Cuckoding.Execution.Environment do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset
  @primary_key {:id, :binary_id, autogenerate: false}
  schema "environments" do
    field :run_id, :binary_id
    field :runner_key, :string
    field :kind, :string
    field :worktree_path, :string
    field :run_dir, :string
    field :base_sha, :string
    field :head_sha, :string
    field :ports_json, :map, default: %{}
    field :port, :integer
    field :preview_url, :string
    field :isolation_claims_json, :map, default: %{}
    field :state, :string, default: "prepared"
    timestamps(type: :utc_datetime_usec)
  end

  def create_changeset(record, attrs) do
    record
    |> cast(attrs, [
      :id,
      :run_id,
      :runner_key,
      :kind,
      :worktree_path,
      :run_dir,
      :base_sha,
      :head_sha,
      :ports_json,
      :port,
      :preview_url,
      :isolation_claims_json
    ])
    |> validate_required([
      :id,
      :run_id,
      :runner_key,
      :kind,
      :worktree_path,
      :run_dir,
      :base_sha,
      :ports_json,
      :isolation_claims_json
    ])
    |> validate_inclusion(:kind, ~w(local_process container remote))
    |> validate_number(:port, greater_than_or_equal_to: 1_024, less_than_or_equal_to: 65_535)
    |> foreign_key_constraint(:run_id)
    |> unique_constraint(:run_id, name: :environments_one_active_run_index)
    |> unique_constraint(:run_id, name: :environments_run_id_index)
    |> unique_constraint(:worktree_path)
    |> unique_constraint(:worktree_path, name: :environments_one_active_worktree_index)
    |> unique_constraint(:run_dir)
    |> unique_constraint(:run_dir, name: :environments_one_active_run_dir_index)
    |> unique_constraint(:port, name: :environments_one_active_port_index)
    |> unique_constraint(:port, name: :environments_port_index)
  end

  def preview_changeset(record, attrs) do
    record
    |> cast(attrs, [:port, :preview_url, :ports_json, :state])
    |> validate_inclusion(:state, ~w(prepared running hibernated stopped failed))
    |> validate_number(:port, greater_than_or_equal_to: 1_024, less_than_or_equal_to: 65_535)
    |> validate_preview_url()
    |> unique_constraint(:port, name: :environments_one_active_port_index)
    |> unique_constraint(:port, name: :environments_port_index)
  end

  @doc false
  def candidate_changeset(record, attrs) do
    record
    |> cast(attrs, [:head_sha])
    |> validate_required([:head_sha])
    |> validate_format(:head_sha, ~r/\A[0-9a-f]{40}\z/)
  end

  defp validate_preview_url(changeset) do
    port = get_field(changeset, :port)
    url = get_field(changeset, :preview_url)

    if (is_nil(port) and is_nil(url)) or url == "http://127.0.0.1:#{port}",
      do: changeset,
      else: add_error(changeset, :preview_url, "must match the allocated loopback port")
  end
end

defmodule Cuckoding.Execution.AgentSession do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset
  @primary_key {:id, :binary_id, autogenerate: false}
  schema "agent_sessions" do
    field :stage_attempt_id, :binary_id
    field :adapter_key, :string
    field :runtime_version, :string
    field :requested_model, :string
    field :actual_model, :string
    field :external_session_id, :string
    field :effective_grant_json, :map, default: %{}
    field :state, :string, default: "created"
    timestamps(type: :utc_datetime_usec)
  end

  def create_changeset(record, attrs) do
    record
    |> cast(attrs, [
      :id,
      :stage_attempt_id,
      :adapter_key,
      :runtime_version,
      :requested_model,
      :effective_grant_json
    ])
    |> validate_required([:id, :stage_attempt_id, :adapter_key, :effective_grant_json])
    |> foreign_key_constraint(:stage_attempt_id)
  end

  def observation_changeset(record, attrs) do
    record
    |> cast(attrs, [:actual_model, :external_session_id, :effective_grant_json, :state])
    |> validate_required([:effective_grant_json, :state])
  end
end

defmodule Cuckoding.Execution.ProcessRecord do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset
  @primary_key {:id, :binary_id, autogenerate: false}
  schema "processes" do
    field :environment_id, :binary_id
    field :agent_session_id, :binary_id
    field :command_id, :binary_id
    field :pid, :integer
    field :pgid, :integer
    field :start_identity, :string
    field :role, :string
    field :state, :string, default: "running"
    field :exit_code, :integer
    field :ended_at, :utc_datetime_usec
    timestamps(type: :utc_datetime_usec)
  end

  def create_changeset(record, attrs) do
    record
    |> cast(attrs, [
      :id,
      :environment_id,
      :agent_session_id,
      :command_id,
      :pid,
      :pgid,
      :start_identity,
      :role
    ])
    |> validate_required([:id, :environment_id, :pid, :pgid, :start_identity, :role])
    |> validate_number(:pid, greater_than: 0)
    |> validate_number(:pgid, greater_than: 0)
    |> foreign_key_constraint(:environment_id)
    |> foreign_key_constraint(:agent_session_id)
    |> foreign_key_constraint(:command_id)
    |> unique_constraint([:pid, :start_identity])
  end

  def finish_changeset(record, attrs) do
    record
    |> cast(attrs, [:state, :exit_code, :ended_at])
    |> validate_required([:state, :ended_at])
    |> validate_inclusion(:state, ~w(exited killed failed))
  end
end

defmodule Cuckoding.Adapters.ProviderAccount do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset
  @primary_key {:id, :binary_id, autogenerate: false}
  schema "provider_accounts" do
    field :adapter_key, :string
    field :label, :string
    field :auth_mode, :string
    field :status, :string, default: "unknown"
    field :capabilities_json, :map, default: %{}
    field :probed_at, :utc_datetime_usec
    timestamps(type: :utc_datetime_usec)
  end

  def create_changeset(record, attrs) do
    record
    |> cast(attrs, [:id, :adapter_key, :label, :auth_mode, :capabilities_json])
    |> validate_required([:id, :adapter_key, :label, :auth_mode, :capabilities_json])
    |> unique_constraint([:adapter_key, :label])
  end
end

defmodule Cuckoding.Power.PowerEvent do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  @kinds ~w(assertion_on assertion_off sleep_gap wake_reconciled unattended_on unattended_off)
  @primary_key {:id, :binary_id, autogenerate: false}

  schema "power_events" do
    field :kind, :string
    field :gap_ms, :integer
    field :affected_runs_json, {:array, :binary_id}, default: []
    field :metadata_json, :map, default: %{}
    field :occurred_at, :utc_datetime_usec
    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def create_changeset(event, attrs) do
    event
    |> cast(attrs, [:id, :kind, :gap_ms, :affected_runs_json, :metadata_json, :occurred_at])
    |> validate_required([:id, :kind, :affected_runs_json, :metadata_json, :occurred_at])
    |> validate_inclusion(:kind, @kinds)
    |> validate_number(:gap_ms, greater_than: 0)
  end
end
