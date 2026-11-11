defmodule Boss.Agents.Detection do
  use Ecto.Schema
  import Ecto.Changeset
  alias Boss.Agents.Metadata

  @primary_key {:agent_id, :string, autogenerate: false}
  schema "agent_detections" do
    field :name, :string
    field :path, :string
    field :version, :string
    field :probe_status, :string
    field :auth_status, :string
    field :capabilities, :map, default: %{}
    field :errors, :map, default: %{"items" => []}
    field :models, :map, default: %{"items" => []}
    field :checked_at, :utc_datetime
    field :models_checked_at, :utc_datetime
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(record, attrs) do
    record
    |> cast(attrs, [
      :agent_id,
      :name,
      :path,
      :version,
      :probe_status,
      :auth_status,
      :capabilities,
      :errors,
      :models,
      :checked_at,
      :models_checked_at
    ])
    |> validate_required([:agent_id, :name, :probe_status, :auth_status])
    |> validate_inclusion(:agent_id, Enum.map(Metadata.ids(), &Atom.to_string/1))
    |> validate_inclusion(:probe_status, ~w(ok missing unsupported failed))
    |> validate_inclusion(:auth_status, ~w(configured stale not_configured unknown))
  end
end
