defmodule AgentDesk.Providers.AcpInstall do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @type t :: %__MODULE__{}

  @statuses ~w(installed removed)

  schema "acp_installs" do
    field :registry_id, :string
    field :name, :string
    field :version, :string
    field :status, :string, default: "installed"
    field :provider_key, :string, default: "acp"
    field :executable, :string
    field :args, {:array, :string}, default: []
    field :distribution, :map, default: %{}

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(install, attrs) do
    install
    |> cast(attrs, [
      :id,
      :registry_id,
      :name,
      :version,
      :status,
      :provider_key,
      :executable,
      :args,
      :distribution
    ])
    |> validate_required([:registry_id, :name, :status, :provider_key])
    |> validate_inclusion(:status, @statuses)
    |> validate_length(:registry_id, max: 120)
    |> validate_length(:name, max: 120)
    |> unique_constraint(:registry_id)
  end
end
