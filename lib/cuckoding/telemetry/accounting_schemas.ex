defmodule Cuckoding.Telemetry.PriceCatalogVersion do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  @rate_keys ~w(input_micros_per_million output_micros_per_million reasoning_micros_per_million cache_read_micros_per_million cache_write_micros_per_million)

  @primary_key {:id, :binary_id, autogenerate: false}
  schema "price_catalog_versions" do
    field :provider, :string
    field :version, :integer
    field :effective_from, :utc_datetime_usec
    field :source_uri, :string
    field :catalog_json, :map
    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def create_changeset(catalog, attrs) do
    catalog
    |> cast(attrs, [:id, :provider, :version, :effective_from, :source_uri, :catalog_json])
    |> validate_required([:id, :provider, :version, :effective_from, :source_uri, :catalog_json])
    |> validate_number(:version, greater_than: 0)
    |> validate_length(:provider, min: 1, max: 100)
    |> validate_length(:source_uri, min: 1, max: 2_048)
    |> validate_catalog()
    |> unique_constraint([:provider, :version])
    |> unique_constraint([:provider, :effective_from])
  end

  defp validate_catalog(changeset) do
    case get_field(changeset, :catalog_json) do
      %{"currency" => currency, "models" => models}
      when is_binary(currency) and is_map(models) and map_size(models) > 0 ->
        if currency =~ ~r/^[A-Z]{3}$/ and Enum.all?(models, &valid_model?/1),
          do: changeset,
          else: add_error(changeset, :catalog_json, "has invalid currency or model rates")

      _other ->
        add_error(changeset, :catalog_json, "must contain currency and model rates")
    end
  end

  defp valid_model?({model, rates}) when is_binary(model) and model != "" and is_map(rates) do
    map_size(rates) > 0 and
      Enum.all?(rates, fn {key, value} ->
        key in @rate_keys and is_integer(value) and value >= 0
      end)
  end

  defp valid_model?(_model), do: false
end

defmodule Cuckoding.Telemetry.UsageRecord do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  @token_fields ~w(input_tokens output_tokens reasoning_tokens cache_read_tokens cache_write_tokens)a

  @primary_key {:id, :binary_id, autogenerate: false}
  schema "usage_records" do
    field :agent_session_id, :binary_id
    field :event_key_hash, :string
    field :provider, :string
    field :model, :string
    field :source, :string
    field :confidence, :string
    field :input_tokens, :integer
    field :output_tokens, :integer
    field :reasoning_tokens, :integer
    field :cache_read_tokens, :integer
    field :cache_write_tokens, :integer
    field :billing_mode, :string
    field :cost_micros, :integer
    field :currency, :string
    field :cost_source, :string
    field :cost_confidence, :string
    field :price_catalog_version_id, :binary_id
    field :formula_json, :map
    field :occurred_at, :utc_datetime_usec
    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def create_changeset(record, attrs) do
    record
    |> cast(attrs, [
      :id,
      :agent_session_id,
      :event_key_hash,
      :provider,
      :model,
      :source,
      :confidence,
      :input_tokens,
      :output_tokens,
      :reasoning_tokens,
      :cache_read_tokens,
      :cache_write_tokens,
      :billing_mode,
      :cost_micros,
      :currency,
      :cost_source,
      :cost_confidence,
      :price_catalog_version_id,
      :formula_json,
      :occurred_at
    ])
    |> validate_required([
      :id,
      :agent_session_id,
      :event_key_hash,
      :provider,
      :source,
      :confidence,
      :billing_mode,
      :cost_source,
      :cost_confidence,
      :occurred_at
    ])
    |> validate_inclusion(:source, ~w(provider_reported unavailable))
    |> validate_inclusion(:confidence, ~w(provider_reported unavailable))
    |> validate_inclusion(:billing_mode, ~w(api subscription unknown))
    |> validate_inclusion(:cost_source, ~w(provider_reported catalog_estimate unavailable))
    |> validate_inclusion(:cost_confidence, ~w(provider_reported catalog_estimate unavailable))
    |> validate_length(:event_key_hash, is: 64)
    |> validate_length(:provider, min: 1, max: 100)
    |> validate_length(:model, min: 1, max: 200)
    |> validate_format(:currency, ~r/^[A-Z]{3}$/)
    |> validate_number(:cost_micros, greater_than_or_equal_to: 0)
    |> validate_tokens()
    |> validate_cost_provenance()
    |> foreign_key_constraint(:agent_session_id)
    |> foreign_key_constraint(:price_catalog_version_id)
    |> unique_constraint([:agent_session_id, :event_key_hash])
  end

  defp validate_tokens(changeset) do
    Enum.reduce(@token_fields, changeset, fn field, current ->
      validate_number(current, field, greater_than_or_equal_to: 0)
    end)
  end

  defp validate_cost_provenance(changeset) do
    fields =
      Map.new(
        ~w(cost_micros currency cost_source cost_confidence price_catalog_version_id formula_json billing_mode)a,
        &{&1, get_field(changeset, &1)}
      )

    if valid_cost_provenance?(fields),
      do: changeset,
      else: add_error(changeset, :cost_source, "does not match cost provenance")
  end

  defp valid_cost_provenance?(%{
         cost_micros: cost,
         currency: currency,
         cost_source: "provider_reported",
         cost_confidence: "provider_reported",
         price_catalog_version_id: nil,
         formula_json: nil
       })
       when is_integer(cost) and is_binary(currency),
       do: true

  defp valid_cost_provenance?(%{
         cost_micros: cost,
         currency: currency,
         cost_source: "catalog_estimate",
         cost_confidence: "catalog_estimate",
         price_catalog_version_id: catalog_id,
         formula_json: formula,
         billing_mode: "api"
       })
       when is_integer(cost) and is_binary(currency) and is_binary(catalog_id) and is_map(formula),
       do: true

  defp valid_cost_provenance?(%{
         cost_micros: nil,
         currency: nil,
         cost_source: "unavailable",
         cost_confidence: "unavailable",
         price_catalog_version_id: nil,
         formula_json: nil
       }),
       do: true

  defp valid_cost_provenance?(_fields), do: false
end

defmodule Cuckoding.Telemetry.OptimizationRecord do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: false}
  schema "optimization_records" do
    field :run_id, :binary_id
    field :plugin_key, :string
    field :kind, :string
    field :raw_units, :integer
    field :optimized_units, :integer
    field :saved_units, :integer
    field :source, :string, default: "plugin_reported"
    field :confidence, :string
    field :estimation_method, :string
    field :metadata_json, :map, default: %{}
    field :recorded_at, :utc_datetime_usec
    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def create_changeset(record, attrs) do
    record
    |> cast(attrs, [
      :id,
      :run_id,
      :plugin_key,
      :kind,
      :raw_units,
      :optimized_units,
      :confidence,
      :estimation_method,
      :metadata_json,
      :recorded_at
    ])
    |> put_change(:source, "plugin_reported")
    |> put_saved_units()
    |> validate_required([
      :id,
      :run_id,
      :plugin_key,
      :kind,
      :raw_units,
      :optimized_units,
      :saved_units,
      :source,
      :confidence,
      :estimation_method,
      :metadata_json,
      :recorded_at
    ])
    |> validate_number(:raw_units, greater_than_or_equal_to: 0)
    |> validate_number(:optimized_units, greater_than_or_equal_to: 0)
    |> validate_number(:saved_units, greater_than_or_equal_to: 0)
    |> validate_inclusion(:confidence, ~w(reported estimated))
    |> validate_length(:plugin_key, min: 1, max: 100)
    |> validate_length(:kind, min: 1, max: 100)
    |> validate_optimized_units()
    |> foreign_key_constraint(:run_id)
  end

  defp put_saved_units(changeset) do
    case {get_field(changeset, :raw_units), get_field(changeset, :optimized_units)} do
      {raw, optimized} when is_integer(raw) and is_integer(optimized) ->
        put_change(changeset, :saved_units, raw - optimized)

      _other ->
        changeset
    end
  end

  defp validate_optimized_units(changeset) do
    raw = get_field(changeset, :raw_units)
    optimized = get_field(changeset, :optimized_units)

    if is_integer(raw) and is_integer(optimized) and optimized > raw,
      do: add_error(changeset, :optimized_units, "cannot exceed raw units"),
      else: changeset
  end
end
