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
