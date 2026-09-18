defmodule Cuckoding.Plugins.Plugin do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: false}

  schema "plugins" do
    field :key, :string
    field :name, :string
    field :kind, :string
    field :version, :string
    field :source, :string
    field :manifest_path, :string
    field :manifest_hash, :string
    field :manifest_json, :map
    field :detected_binaries_json, :map, default: %{}
    field :health, :string
    field :detected_at, :utc_datetime_usec
    field :last_error, :string
    has_many :activations, Cuckoding.Plugins.Activation
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(plugin, attrs) do
    plugin
    |> cast(attrs, [
      :id,
      :key,
      :name,
      :kind,
      :version,
      :source,
      :manifest_path,
      :manifest_hash,
      :manifest_json,
      :detected_binaries_json,
      :health,
      :detected_at,
      :last_error
    ])
    |> validate_required([
      :id,
      :key,
      :name,
      :kind,
      :version,
      :source,
      :manifest_path,
      :manifest_hash,
      :manifest_json,
      :detected_binaries_json,
      :health,
      :detected_at
    ])
    |> validate_inclusion(:kind, Cuckoding.Plugins.Manifest.kinds())
    |> validate_inclusion(:source, ~w(bundled user))
    |> validate_inclusion(:health, ~w(available missing version_mismatch unhealthy disabled))
    |> unique_constraint(:key)
  end

  def health_changeset(plugin, attrs) do
    plugin
    |> cast(attrs, [:health, :last_error])
    |> validate_required([:health])
    |> validate_inclusion(:health, ~w(available missing version_mismatch unhealthy disabled))
  end
end

defmodule Cuckoding.Plugins.Activation do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: false}

  schema "plugin_activations" do
    field :plugin_id, :binary_id
    belongs_to :plugin, Cuckoding.Plugins.Plugin, define_field: false
    field :scope_type, :string
    field :scope_id, :binary_id
    field :enabled, :boolean
    field :permissions_json, :map
    field :config_json, :map, default: %{}
    field :network, :string
    field :approval_kind, :string
    field :approved_by, :string
    field :approval_reason, :string
    field :approved_at, :utc_datetime_usec
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(activation, attrs) do
    activation
    |> cast(attrs, [
      :id,
      :plugin_id,
      :scope_type,
      :scope_id,
      :enabled,
      :permissions_json,
      :config_json,
      :network,
      :approval_kind,
      :approved_by,
      :approval_reason,
      :approved_at
    ])
    |> validate_required([
      :id,
      :plugin_id,
      :scope_type,
      :enabled,
      :permissions_json,
      :config_json,
      :network,
      :approval_kind,
      :approved_by,
      :approval_reason,
      :approved_at
    ])
    |> validate_inclusion(:scope_type, ~w(global project board role stage))
    |> validate_inclusion(:network, ~w(none loopback external))
    |> validate_inclusion(:approval_kind, ~w(standard loopback_network external_network))
    |> validate_length(:approved_by, min: 1, max: 200)
    |> validate_length(:approval_reason, min: 1, max: 500)
    |> validate_scope_id()
    |> foreign_key_constraint(:plugin_id)
    |> unique_constraint(:plugin_id, name: :plugin_activations_global_plugin_index)
    |> unique_constraint([:plugin_id, :scope_type, :scope_id],
      name: :plugin_activations_scoped_plugin_index
    )
    |> check_constraint(:scope_id, name: :plugin_activations_scope_id_matches_type)
    |> check_constraint(:approval_kind, name: :plugin_activations_network_approval_matches)
  end

  defp validate_scope_id(changeset) do
    case {get_field(changeset, :scope_type), get_field(changeset, :scope_id)} do
      {"global", nil} -> changeset
      {"global", _id} -> add_error(changeset, :scope_id, "must be empty for global scope")
      {_scope, nil} -> add_error(changeset, :scope_id, "is required outside global scope")
      {_scope, _id} -> changeset
    end
  end
end
