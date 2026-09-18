defmodule Cuckoding.Plugins.Context do
  @moduledoc "Short-lived, run-scoped authority passed to one plugin invocation."

  @enforce_keys [
    :kind,
    :plugin_id,
    :plugin_key,
    :manifest_hash,
    :run_id,
    :activation_id,
    :permissions,
    :capabilities,
    :config,
    :network,
    :capability_token,
    :ttl_seconds
  ]
  defstruct @enforce_keys ++ [stage_id: nil, role_id: nil]

  @type t :: %__MODULE__{
          kind: String.t(),
          plugin_id: String.t(),
          plugin_key: String.t(),
          manifest_hash: String.t(),
          run_id: String.t(),
          stage_id: String.t() | nil,
          role_id: String.t() | nil,
          activation_id: String.t(),
          permissions: map(),
          capabilities: [String.t()],
          config: map(),
          network: String.t(),
          capability_token: String.t(),
          ttl_seconds: pos_integer()
        }
end

defimpl Inspect, for: Cuckoding.Plugins.Context do
  import Inspect.Algebra

  def inspect(context, options) do
    fields = [
      kind: context.kind,
      plugin_key: context.plugin_key,
      run_id: context.run_id,
      network: context.network,
      capability_token: "[REDACTED]"
    ]

    concat(["#Cuckoding.Plugins.Context<", to_doc(fields, options), ">"])
  end
end

defmodule Cuckoding.Plugins.Capability do
  @moduledoc "Issues and verifies signed plugin authority tied to durable activation state."

  alias Cuckoding.Plugins.Context
  alias Cuckoding.Plugins.Registry

  @salt "cuckoding-plugin-capability-v1"
  @default_ttl 300
  @maximum_ttl 900

  def issue(plugin_id, run_id, options \\ [])

  def issue(plugin_id, run_id, options)
      when is_binary(plugin_id) and is_binary(run_id) do
    ttl = Keyword.get(options, :ttl_seconds, @default_ttl)

    with true <- ttl in 1..@maximum_ttl,
         {:ok, {plugin, activation}} <- Registry.effective_activation(plugin_id, run_id, options) do
      payload = %{
        "kind" => plugin.kind,
        "plugin_id" => plugin.id,
        "plugin_key" => plugin.key,
        "manifest_hash" => plugin.manifest_hash,
        "run_id" => run_id,
        "stage_id" => Keyword.get(options, :stage_id),
        "role_id" => Keyword.get(options, :role_id),
        "activation_id" => activation.id,
        "permissions" => activation.permissions_json,
        "capabilities" => plugin.manifest_json["capabilities"],
        "config" => activation.config_json,
        "network" => activation.network,
        "ttl_seconds" => ttl
      }

      {:ok,
       payload
       |> context(Phoenix.Token.sign(endpoint(options), @salt, payload))}
    else
      false -> {:error, :invalid_plugin_capability_ttl}
      {:error, reason} -> {:error, reason}
    end
  end

  def issue(_plugin_id, _run_id, _options), do: {:error, :invalid_plugin_capability_scope}

  def verify(context, options \\ [])

  def verify(%Context{} = context, options) do
    with true <- context.ttl_seconds in 1..@maximum_ttl,
         {:ok, payload} <-
           Phoenix.Token.verify(endpoint(options), @salt, context.capability_token,
             max_age: context.ttl_seconds
           ),
         true <- payload == payload(context),
         {:ok, {plugin, activation}} <-
           Registry.effective_activation(
             context.plugin_id,
             context.run_id,
             scope_options(context)
           ),
         true <- plugin.kind == context.kind and plugin.key == context.plugin_key,
         true <- plugin.manifest_hash == context.manifest_hash,
         true <- activation.id == context.activation_id,
         true <- activation.permissions_json == context.permissions,
         true <- activation.config_json == context.config,
         true <- activation.network == context.network do
      :ok
    else
      _reason -> {:error, :invalid_plugin_capability}
    end
  end

  def verify(_context, _options), do: {:error, :invalid_plugin_capability}

  defp context(payload, token) do
    struct!(Context,
      kind: payload["kind"],
      plugin_id: payload["plugin_id"],
      plugin_key: payload["plugin_key"],
      manifest_hash: payload["manifest_hash"],
      run_id: payload["run_id"],
      stage_id: payload["stage_id"],
      role_id: payload["role_id"],
      activation_id: payload["activation_id"],
      permissions: payload["permissions"],
      capabilities: payload["capabilities"],
      config: payload["config"],
      network: payload["network"],
      capability_token: token,
      ttl_seconds: payload["ttl_seconds"]
    )
  end

  defp payload(context) do
    %{
      "kind" => context.kind,
      "plugin_id" => context.plugin_id,
      "plugin_key" => context.plugin_key,
      "manifest_hash" => context.manifest_hash,
      "run_id" => context.run_id,
      "stage_id" => context.stage_id,
      "role_id" => context.role_id,
      "activation_id" => context.activation_id,
      "permissions" => context.permissions,
      "capabilities" => context.capabilities,
      "config" => context.config,
      "network" => context.network,
      "ttl_seconds" => context.ttl_seconds
    }
  end

  defp scope_options(context) do
    [stage_id: context.stage_id, role_id: context.role_id]
  end

  defp endpoint(options), do: Keyword.get(options, :endpoint, CuckodingWeb.Endpoint)
end

defmodule Cuckoding.Plugins.Measurement do
  @moduledoc "A numeric plugin claim with explicit provenance."

  @derive {Jason.Encoder, only: [:name, :value, :unit, :source]}
  @enforce_keys [:name, :value, :unit, :source]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          name: String.t(),
          value: number(),
          unit: String.t(),
          source: String.t()
        }
end

defmodule Cuckoding.Plugins.Result do
  @moduledoc "Validated public plugin output plus an optional secret-store-only value."

  alias Cuckoding.Plugins.Measurement
  alias Cuckoding.Security.Redactor

  @maximum_bytes 1_048_576
  @maximum_measurements 100
  @sources ~w(measured reported estimated)

  defstruct data: %{}, measurements: [], private: nil

  @type t :: %__MODULE__{
          data: map(),
          measurements: [Measurement.t()],
          private: map() | nil
        }

  def normalize(result, kind, options \\ [])

  def normalize({:ok, %__MODULE__{} = result}, kind, options) do
    data = Redactor.redact(result.data, Keyword.get(options, :secrets, []))

    with :ok <- public_data(data),
         :ok <- measurements(result.measurements),
         :ok <- private(kind, result.private),
         {:ok, encoded} <- Jason.encode(%{data: data, measurements: result.measurements}),
         true <- byte_size(encoded) <= @maximum_bytes do
      {:ok, %{result | data: data}}
    else
      false -> {:error, :plugin_output_too_large}
      {:error, reason} -> {:error, reason}
    end
  end

  def normalize({:error, _reason}, _kind, _options), do: {:error, :plugin_failed}
  def normalize(_result, _kind, _options), do: {:error, :invalid_plugin_output}

  defp public_data(data) when is_map(data) do
    with true <- Enum.all?(Map.keys(data), &is_binary/1),
         false <- contains_number?(data) do
      :ok
    else
      false -> {:error, :invalid_plugin_output}
      true -> {:error, :unlabeled_numeric_plugin_output}
    end
  end

  defp public_data(_data), do: {:error, :invalid_plugin_output}

  defp measurements(values)
       when is_list(values) and length(values) <= @maximum_measurements do
    if Enum.all?(values, &measurement?/1),
      do: :ok,
      else: {:error, :invalid_plugin_measurement}
  end

  defp measurements(_values), do: {:error, :invalid_plugin_measurement}

  defp measurement?(%Measurement{name: name, value: value, unit: unit, source: source}) do
    is_binary(name) and name != "" and is_number(value) and is_binary(unit) and unit != "" and
      source in @sources
  end

  defp measurement?(_measurement), do: false

  defp private("secret_store", %{"value" => value})
       when is_binary(value) and byte_size(value) <= @maximum_bytes,
       do: :ok

  defp private("secret_store", nil), do: :ok
  defp private(_kind, nil), do: :ok
  defp private(_kind, _value), do: {:error, :private_plugin_output_refused}

  defp contains_number?(value) when is_number(value), do: true

  defp contains_number?(value) when is_map(value),
    do: Enum.any?(value, fn {_key, item} -> contains_number?(item) end)

  defp contains_number?(value) when is_list(value), do: Enum.any?(value, &contains_number?/1)
  defp contains_number?(_value), do: false
end

defimpl Inspect, for: Cuckoding.Plugins.Result do
  import Inspect.Algebra

  def inspect(result, options) do
    fields = [data: result.data, measurements: result.measurements, private: "[REDACTED]"]
    concat(["#Cuckoding.Plugins.Result<", to_doc(fields, options), ">"])
  end
end

defmodule Cuckoding.Plugins.Contracts do
  @moduledoc "Closed plugin-kind operation registry and guarded invocation boundary."

  alias Cuckoding.Plugins.Capability
  alias Cuckoding.Plugins.Context
  alias Cuckoding.Plugins.Result

  @contracts %{
    "knowledge_backend" =>
      {Cuckoding.Plugins.Kinds.KnowledgeBackend,
       [:index, :search, :recall, :write_candidate, :health]},
    "shell_filter" => {Cuckoding.Plugins.Kinds.ShellFilter, [:wrap, :filter, :analytics]},
    "instruction_skill" => {Cuckoding.Plugins.Kinds.InstructionSkill, [:package]},
    "mcp_server" => {Cuckoding.Plugins.Kinds.McpServer, [:configuration]},
    "runner" =>
      {Cuckoding.Plugins.Kinds.Runner,
       [:prepare, :start, :exec, :pause, :hibernate, :resume, :inspect, :stream_events, :destroy]},
    "metric_source" => {Cuckoding.Plugins.Kinds.MetricSource, [:sample]},
    "vcs_host" => {Cuckoding.Plugins.Kinds.VcsHost, [:handoff]},
    "secret_store" => {Cuckoding.Plugins.Kinds.SecretStore, [:put, :fetch, :delete]},
    "notifier" => {Cuckoding.Plugins.Kinds.Notifier, [:notify]}
  }

  def list, do: @contracts

  def behaviour(kind) do
    case @contracts[kind] do
      {behaviour, _operations} -> {:ok, behaviour}
      nil -> {:error, :unsupported_plugin_kind}
    end
  end

  def operations(kind) do
    case @contracts[kind] do
      {_behaviour, operations} -> {:ok, operations}
      nil -> {:error, :unsupported_plugin_kind}
    end
  end

  def call(kind, implementation, operation, input, context, options \\ [])

  def call(kind, implementation, operation, input, %Context{} = context, options)
      when is_atom(implementation) and is_atom(operation) and is_map(input) do
    with {:ok, operations} <- operations(kind),
         :ok <- matching_kind(context, kind),
         :ok <- allowed_operation(operation, operations),
         :ok <- Capability.verify(context, options),
         :ok <- valid_implementation(implementation, operation) do
      invoke(implementation, operation, input, context, kind, options)
    else
      {:error, reason} -> {:error, reason}
    end
  end

  def call(_kind, _implementation, _operation, _input, _context, _options),
    do: {:error, :invalid_plugin_invocation}

  defp matching_kind(%Context{kind: kind}, kind), do: :ok
  defp matching_kind(_context, _kind), do: {:error, :plugin_kind_mismatch}

  defp allowed_operation(operation, operations) do
    if operation in operations, do: :ok, else: {:error, :unsupported_plugin_operation}
  end

  defp valid_implementation(implementation, operation) do
    if Code.ensure_loaded?(implementation) and function_exported?(implementation, operation, 2),
      do: :ok,
      else: {:error, :invalid_plugin_implementation}
  end

  defp invoke(implementation, operation, input, context, kind, options) do
    implementation
    |> apply(operation, [input, context])
    |> Result.normalize(kind, options)
  rescue
    _error -> {:error, :plugin_failed}
  catch
    _kind, _reason -> {:error, :plugin_failed}
  end
end
