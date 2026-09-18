defmodule Cuckoding.Knowledge.Job do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: false}
  schema "knowledge_jobs" do
    field :kind, :string, default: "extract"
    field :scope_type, :string, default: "run"
    field :scope_id, :binary_id
    field :state, :string
    field :runtime, :string
    field :policy_version, :string
    field :input_budget, :integer
    field :input_hash, :string
    field :started_at, :utc_datetime_usec
    field :finished_at, :utc_datetime_usec
    field :summary_json, :map, default: %{}
    timestamps(type: :utc_datetime_usec)
  end

  def create_changeset(job, attrs) do
    job
    |> cast(attrs, [
      :id,
      :kind,
      :scope_type,
      :scope_id,
      :state,
      :runtime,
      :policy_version,
      :input_budget,
      :input_hash,
      :started_at,
      :finished_at,
      :summary_json
    ])
    |> validate_required([
      :id,
      :kind,
      :scope_type,
      :scope_id,
      :state,
      :runtime,
      :policy_version,
      :input_budget,
      :input_hash,
      :started_at,
      :summary_json
    ])
    |> validate_inclusion(:kind, ["extract"])
    |> validate_inclusion(:scope_type, ["run"])
    |> validate_inclusion(:state, ~w(running completed failed))
    |> validate_number(:input_budget, greater_than: 0, less_than_or_equal_to: 65_536)
    |> validate_format(:input_hash, ~r/^[0-9a-f]{64}$/)
    |> unique_constraint([:kind, :scope_type, :scope_id])
  end

  def finish_changeset(job, attrs) do
    job
    |> cast(attrs, [:state, :finished_at, :summary_json])
    |> validate_required([:state, :finished_at, :summary_json])
    |> validate_inclusion(:state, ~w(completed failed))
  end
end

defmodule Cuckoding.Knowledge.ConsolidationJob do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: false}
  schema "knowledge_consolidation_jobs" do
    field :project_id, :binary_id
    field :state, :string
    field :input_hash, :string
    field :policy_version, :string
    field :input_budget, :integer
    field :revision, :integer, default: 1
    field :checkpoint_json, :map, default: %{}
    field :summary_json, :map, default: %{}
    field :started_at, :utc_datetime_usec
    field :finished_at, :utc_datetime_usec
    timestamps(type: :utc_datetime_usec)
  end

  def create_changeset(job, attrs) do
    job
    |> cast(attrs, [
      :id,
      :project_id,
      :state,
      :input_hash,
      :policy_version,
      :input_budget,
      :revision,
      :checkpoint_json,
      :summary_json,
      :started_at,
      :finished_at
    ])
    |> validate_job()
    |> foreign_key_constraint(:project_id)
    |> unique_constraint(:project_id)
  end

  def restart_changeset(job, attrs) do
    job
    |> cast(attrs, [
      :state,
      :input_hash,
      :started_at,
      :finished_at,
      :summary_json,
      :checkpoint_json,
      :revision
    ])
    |> validate_job()
  end

  def checkpoint_changeset(job, attrs) do
    job
    |> cast(attrs, [:checkpoint_json])
    |> validate_required([:checkpoint_json])
  end

  def finish_changeset(job, attrs) do
    job
    |> cast(attrs, [:state, :finished_at, :summary_json])
    |> validate_required([:state, :finished_at, :summary_json])
    |> validate_inclusion(:state, ~w(completed failed))
  end

  defp validate_job(changeset) do
    changeset
    |> validate_required([
      :id,
      :project_id,
      :state,
      :input_hash,
      :policy_version,
      :input_budget,
      :revision,
      :checkpoint_json,
      :summary_json,
      :started_at
    ])
    |> validate_inclusion(:state, ["running"])
    |> validate_format(:input_hash, ~r/^[0-9a-f]{64}$/)
    |> validate_number(:input_budget, greater_than: 0, less_than_or_equal_to: 65_536)
    |> validate_number(:revision, greater_than: 0)
  end
end

defmodule Cuckoding.Knowledge.IndexRevision do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: false}
  schema "knowledge_index_revisions" do
    field :consolidation_job_id, :binary_id
    field :project_id, :binary_id
    field :job_revision, :integer
    field :previous_hash, :string
    field :content_hash, :string
    field :content, :string
    field :recorded_at, :utc_datetime_usec
    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def create_changeset(revision, attrs) do
    revision
    |> cast(attrs, [
      :id,
      :consolidation_job_id,
      :project_id,
      :job_revision,
      :previous_hash,
      :content_hash,
      :content,
      :recorded_at
    ])
    |> validate_required([
      :id,
      :consolidation_job_id,
      :project_id,
      :job_revision,
      :content_hash,
      :content,
      :recorded_at
    ])
    |> validate_number(:job_revision, greater_than: 0)
    |> validate_length(:content, max: 32_768)
    |> validate_format(:content_hash, ~r/^[0-9a-f]{64}$/)
    |> validate_optional_hash(:previous_hash)
    |> foreign_key_constraint(:consolidation_job_id)
    |> foreign_key_constraint(:project_id)
    |> unique_constraint([:consolidation_job_id, :job_revision])
    |> unique_constraint([:project_id, :job_revision])
  end

  defp validate_optional_hash(changeset, field) do
    case get_field(changeset, field) do
      nil -> changeset
      _value -> validate_format(changeset, field, ~r/^[0-9a-f]{64}$/)
    end
  end
end

defmodule Cuckoding.Knowledge.Candidate do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: false}
  schema "knowledge_candidates" do
    field :extraction_job_id, :binary_id
    field :project_id, :binary_id
    field :kind, :string
    field :operation, :string
    field :target_item_id, :binary_id
    field :title, :string
    field :content, :string
    field :content_hash, :string
    field :confidence, :float
    field :evidence_json, :map
    field :redaction_state, :string
    field :decision, :string, default: "pending"
    timestamps(type: :utc_datetime_usec)
  end

  def create_changeset(candidate, attrs) do
    candidate
    |> cast(attrs, [
      :id,
      :extraction_job_id,
      :project_id,
      :kind,
      :operation,
      :target_item_id,
      :title,
      :content,
      :content_hash,
      :confidence,
      :evidence_json,
      :redaction_state,
      :decision
    ])
    |> validate_required([
      :id,
      :extraction_job_id,
      :project_id,
      :kind,
      :operation,
      :title,
      :content,
      :content_hash,
      :confidence,
      :evidence_json,
      :redaction_state,
      :decision
    ])
    |> validate_inclusion(:kind, ~w(fact decision pattern recipe observation))
    |> validate_inclusion(:operation, ~w(add update supersede noop))
    |> validate_inclusion(:decision, ~w(pending accepted rejected))
    |> validate_inclusion(:redaction_state, ["redacted"])
    |> validate_length(:title, min: 1, max: 200)
    |> validate_length(:content, min: 1, max: 32_768)
    |> validate_number(:confidence, greater_than_or_equal_to: 0.0, less_than_or_equal_to: 1.0)
    |> validate_format(:content_hash, ~r/^[0-9a-f]{64}$/)
    |> validate_target()
    |> foreign_key_constraint(:extraction_job_id)
    |> foreign_key_constraint(:project_id)
    |> foreign_key_constraint(:target_item_id)
    |> unique_constraint([:extraction_job_id, :content_hash, :operation])
  end

  defp validate_target(changeset) do
    operation = get_field(changeset, :operation)
    target = get_field(changeset, :target_item_id)

    if (operation == "add" and is_nil(target)) or (operation != "add" and is_binary(target)),
      do: changeset,
      else: add_error(changeset, :target_item_id, "does not match the memory operation")
  end
end
