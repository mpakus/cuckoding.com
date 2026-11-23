defmodule Boss.Tasks.Entry do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  @roles ~w(analytic implementer reviewer owner system)
  @kinds ~w(comment spec_update stage_log)
  @agents ~w(codex claude cursor hermes pi opencode)

  schema "task_entries" do
    field :project_id, :integer
    field :task_id, :integer
    field :delivery_id, :string
    field :spec_revision_id, :integer
    field :author_role, :string
    field :agent_id, :string
    field :model_id, :string
    field :kind, :string
    field :cycle, :integer
    field :stage, :string
    field :summary, :string
    field :body, :string, default: ""
    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def changeset(entry, attrs) do
    entry
    |> cast(attrs, [
      :project_id,
      :task_id,
      :delivery_id,
      :spec_revision_id,
      :author_role,
      :agent_id,
      :model_id,
      :kind,
      :cycle,
      :stage,
      :summary,
      :body
    ])
    |> validate_required([:project_id, :task_id, :author_role, :kind, :summary])
    |> validate_inclusion(:author_role, @roles)
    |> validate_inclusion(:kind, @kinds)
    |> validate_agent()
    |> validate_length(:summary, min: 1, max: 240, count: :bytes)
    |> validate_length(:body, max: 8192, count: :bytes)
    |> validate_length(:model_id, max: 160)
    |> validate_length(:stage, max: 64)
  end

  defp validate_agent(changeset) do
    case get_field(changeset, :agent_id) do
      nil -> changeset
      val when val in @agents -> changeset
      _ -> add_error(changeset, :agent_id, "is invalid")
    end
  end
end
