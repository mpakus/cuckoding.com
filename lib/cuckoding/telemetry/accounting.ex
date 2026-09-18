defmodule Cuckoding.Telemetry.Accounting do
  @moduledoc "Durable provider usage, reproducible cost estimates, and separate plugin claims."

  import Ecto.Query

  alias Cuckoding.Adapters.Types
  alias Cuckoding.Execution.AgentSession
  alias Cuckoding.Identifier
  alias Cuckoding.Repo
  alias Cuckoding.Security.Redactor
  alias Cuckoding.Telemetry.OptimizationRecord
  alias Cuckoding.Telemetry.PriceCatalogVersion
  alias Cuckoding.Telemetry.UsageRecord

  @micros_per_unit 1_000_000
  @rounding_offset div(@micros_per_unit, 2)
  @sqlite_integer_max 9_223_372_036_854_775_807
  @dimensions [
    {:input_tokens, "input_micros_per_million"},
    {:output_tokens, "output_micros_per_million"},
    {:reasoning_tokens, "reasoning_micros_per_million"},
    {:cache_read_tokens, "cache_read_micros_per_million"},
    {:cache_write_tokens, "cache_write_micros_per_million"}
  ]

  def publish_catalog(attrs) when is_map(attrs) do
    attrs = Map.put_new(attrs, :id, Identifier.generate())

    %PriceCatalogVersion{}
    |> PriceCatalogVersion.create_changeset(attrs)
    |> Repo.insert()
  end

  def record_usage(agent_session_id, event_key, usage, options \\ [])

  def record_usage(agent_session_id, event_key, %Types.Usage{} = usage, options)
      when is_binary(agent_session_id) and is_binary(event_key) and event_key != "" do
    with %AgentSession{} = session <- Repo.get(AgentSession, agent_session_id),
         {:ok, source} <- usage_source(usage),
         {:ok, billing_mode} <- billing_mode(Keyword.get(options, :billing_mode, :unknown)),
         occurred_at <- Keyword.get(options, :occurred_at, Cuckoding.Clock.wall_now()),
         provider <- Keyword.get(options, :provider, session.adapter_key),
         model <- Keyword.get(options, :model, session.actual_model || session.requested_model),
         {:ok, cost} <- cost(usage, source, provider, model, billing_mode, occurred_at) do
      attrs =
        usage
        |> usage_attrs()
        |> Map.merge(cost)
        |> Map.merge(%{
          id: Identifier.generate(),
          agent_session_id: session.id,
          event_key_hash: hash(event_key),
          provider: provider,
          model: model,
          source: source,
          confidence: source,
          billing_mode: billing_mode,
          occurred_at: occurred_at
        })

      persist_usage(attrs)
    else
      nil -> {:error, :agent_session_not_found}
      {:error, _reason} = error -> error
    end
  end

  def record_usage(_agent_session_id, _event_key, %Types.Usage{}, _options),
    do: {:error, :invalid_event_key}

  def record_optimization(attrs, options \\ []) when is_map(attrs) do
    metadata =
      attrs |> Map.get(:metadata_json, %{}) |> Redactor.redact(Keyword.get(options, :redact, []))

    attrs =
      attrs
      |> Map.put_new(:id, Identifier.generate())
      |> Map.put_new(:recorded_at, Cuckoding.Clock.wall_now())
      |> Map.put(:metadata_json, metadata)

    %OptimizationRecord{}
    |> OptimizationRecord.create_changeset(attrs)
    |> Repo.insert()
  end

  def recent_usage(limit \\ 10) when is_integer(limit) and limit in 1..100 do
    Repo.all(
      from(record in UsageRecord,
        order_by: [desc: record.occurred_at, desc: record.id],
        limit: ^limit
      )
    )
  end

  def cost_label(%UsageRecord{cost_micros: nil}), do: "Cost unavailable"

  def cost_label(%UsageRecord{} = record) do
    prefix = if record.cost_source == "catalog_estimate", do: "≈ ", else: ""
    prefix <> format_micros(record.cost_micros, record.currency)
  end

  def cost_source_label(%UsageRecord{cost_source: "provider_reported"}),
    do: "Provider-reported"

  def cost_source_label(%UsageRecord{cost_source: "catalog_estimate"}),
    do: "Catalog estimate"

  def cost_source_label(%UsageRecord{}), do: "Unavailable"

  def optimization_label(%OptimizationRecord{saved_units: saved, confidence: "estimated"}),
    do: "≈ #{saved} saved"

  def optimization_label(%OptimizationRecord{saved_units: saved}), do: "#{saved} saved"

  defp persist_usage(attrs) do
    changeset = UsageRecord.create_changeset(%UsageRecord{}, attrs)

    if changeset.valid? do
      Repo.transaction(fn ->
        Repo.get_by(UsageRecord,
          agent_session_id: attrs.agent_session_id,
          event_key_hash: attrs.event_key_hash
        ) || insert_usage(changeset)
      end)
    else
      {:error, changeset}
    end
  end

  defp insert_usage(changeset) do
    case Repo.insert(changeset) do
      {:ok, record} -> record
      {:error, failed_changeset} -> Repo.rollback(failed_changeset)
    end
  end

  defp usage_source(%Types.Usage{source: "provider", confidence: "reported"}),
    do: {:ok, "provider_reported"}

  defp usage_source(%Types.Usage{source: "unavailable", confidence: "unavailable"}),
    do: {:ok, "unavailable"}

  defp usage_source(_usage), do: {:error, :invalid_usage_provenance}

  defp billing_mode(mode) when mode in [:api, "api"], do: {:ok, "api"}
  defp billing_mode(mode) when mode in [:subscription, "subscription"], do: {:ok, "subscription"}
  defp billing_mode(mode) when mode in [:unknown, "unknown"], do: {:ok, "unknown"}
  defp billing_mode(_mode), do: {:error, :invalid_billing_mode}

  defp cost(
         %Types.Usage{cost_micros: micros, currency: currency},
         source,
         _provider,
         _model,
         _mode,
         _at
       )
       when is_integer(micros) and micros >= 0 and is_binary(currency) and
              source == "provider_reported" do
    if currency =~ ~r/^[A-Z]{3}$/ do
      {:ok,
       %{
         cost_micros: micros,
         currency: currency,
         cost_source: "provider_reported",
         cost_confidence: "provider_reported",
         price_catalog_version_id: nil,
         formula_json: nil
       }}
    else
      {:error, :invalid_reported_cost}
    end
  end

  defp cost(
         %Types.Usage{cost_micros: nil, currency: nil} = usage,
         "provider_reported",
         provider,
         model,
         "api",
         at
       ),
       do: estimate(usage, provider, model, at)

  defp cost(
         %Types.Usage{cost_micros: nil, currency: nil},
         _source,
         _provider,
         _model,
         _mode,
         _at
       ),
       do: {:ok, unavailable_cost()}

  defp cost(_usage, _source, _provider, _model, _mode, _at),
    do: {:error, :invalid_reported_cost}

  defp estimate(usage, provider, model, occurred_at) do
    catalog =
      PriceCatalogVersion
      |> where(
        [catalog],
        catalog.provider == ^provider and catalog.effective_from <= ^occurred_at
      )
      |> order_by([catalog], desc: catalog.effective_from, desc: catalog.version)
      |> Repo.all()
      |> Enum.find(&is_map(get_in(&1.catalog_json, ["models", model])))

    with %PriceCatalogVersion{} <- catalog,
         {:ok, breakdown} <- breakdown(usage, catalog.catalog_json["models"][model]),
         {:ok, total_numerator} <- total_numerator(breakdown) do
      formula = %{
        "denominator" => @micros_per_unit,
        "rounding" => "nearest_micro_half_up",
        "model" => model,
        "dimensions" => breakdown,
        "total_numerator" => total_numerator
      }

      {:ok,
       %{
         cost_micros: div(total_numerator + @rounding_offset, @micros_per_unit),
         currency: catalog.catalog_json["currency"],
         cost_source: "catalog_estimate",
         cost_confidence: "catalog_estimate",
         price_catalog_version_id: catalog.id,
         formula_json: formula
       }}
    else
      nil -> {:ok, unavailable_cost()}
      :missing_rate -> {:ok, unavailable_cost()}
      {:error, _reason} = error -> error
    end
  end

  defp breakdown(usage, rates) do
    if explicit_usage?(usage) do
      Enum.reduce_while(@dimensions, {:ok, []}, fn dimension, result ->
        accumulate_dimension(dimension, result, usage, rates)
      end)
      |> reverse_breakdown()
    else
      :missing_rate
    end
  end

  defp explicit_usage?(usage),
    do: Enum.any?(@dimensions, fn {field, _rate_key} -> is_integer(Map.get(usage, field)) end)

  defp accumulate_dimension({field, rate_key}, {:ok, items}, usage, rates) do
    case priced_dimension(usage, rates, field, rate_key) do
      {:ok, item} -> {:cont, {:ok, [item | items]}}
      :skip -> {:cont, {:ok, items}}
      :missing_rate -> {:halt, :missing_rate}
    end
  end

  defp priced_dimension(usage, rates, field, rate_key) do
    case {Map.get(usage, field), rates[rate_key]} do
      {tokens, rate} when is_integer(tokens) and tokens > 0 and is_integer(rate) ->
        {:ok,
         %{
           "dimension" => Atom.to_string(field),
           "tokens" => tokens,
           "rate_micros_per_million" => rate,
           "numerator" => tokens * rate
         }}

      {tokens, _rate} when is_integer(tokens) and tokens > 0 ->
        :missing_rate

      _other ->
        :skip
    end
  end

  defp reverse_breakdown({:ok, items}), do: {:ok, Enum.reverse(items)}
  defp reverse_breakdown(:missing_rate), do: :missing_rate

  defp total_numerator(breakdown) do
    total = Enum.reduce(breakdown, 0, &(&1["numerator"] + &2))

    if total <= @sqlite_integer_max - @rounding_offset,
      do: {:ok, total},
      else: {:error, :cost_overflow}
  end

  defp unavailable_cost do
    %{
      cost_micros: nil,
      currency: nil,
      cost_source: "unavailable",
      cost_confidence: "unavailable",
      price_catalog_version_id: nil,
      formula_json: nil
    }
  end

  defp usage_attrs(usage) do
    Map.take(usage, [
      :input_tokens,
      :output_tokens,
      :reasoning_tokens,
      :cache_read_tokens,
      :cache_write_tokens
    ])
  end

  defp hash(value), do: :crypto.hash(:sha256, value) |> Base.encode16(case: :lower)

  defp format_micros(micros, currency) do
    whole = div(micros, @micros_per_unit)

    fractional =
      micros |> rem(@micros_per_unit) |> Integer.to_string() |> String.pad_leading(6, "0")

    "$#{whole}.#{fractional} #{currency}"
  end
end
