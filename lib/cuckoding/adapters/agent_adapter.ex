defmodule Cuckoding.Adapters.AgentAdapter do
  @moduledoc "Provider-neutral host runtime contract. Provider output is always untrusted."

  alias Cuckoding.Adapters.Types

  @callback probe(keyword()) :: {:ok, Types.Probe.t()} | {:error, Types.Error.t()}
  @callback capabilities(keyword()) :: {:ok, Types.Capabilities.t()} | {:error, Types.Error.t()}
  @callback render_config(Types.StageRequest.t(), keyword()) ::
              {:ok, Types.EffectiveGrant.t()} | {:error, Types.Error.t()}
  @callback start(Types.StageRequest.t(), keyword()) ::
              {:ok, Types.Session.t()} | {:error, Types.Error.t()}
  @callback send(Types.Session.t(), map(), keyword()) ::
              {:ok, Types.Event.t()} | {:error, Types.Error.t()}
  @callback pause(Types.Session.t(), keyword()) :: {:ok, map()} | {:error, Types.Error.t()}
  @callback resume(Types.Session.t() | Types.ContinuationPackage.t(), map(), keyword()) ::
              {:ok, Types.Session.t()} | {:error, Types.Error.t()}
  @callback recover(Types.Session.t(), map(), keyword()) ::
              {:ok, Types.Session.t()} | {:error, Types.Error.t()}
  @callback cancel(Types.Session.t(), keyword()) ::
              {:ok, Types.Session.t()} | {:error, Types.Error.t()}
  @callback inspect(Types.Session.t(), keyword()) :: {:ok, map()} | {:error, Types.Error.t()}
  @callback decode_event(map(), keyword()) ::
              {:ok, Types.Event.t()} | {:error, Types.Error.t()}
  @callback collect_usage(Types.Session.t(), keyword()) ::
              {:ok, Types.Usage.t()} | {:error, Types.Error.t()}
end

defmodule Cuckoding.Adapters.Types do
  @moduledoc "Typed values shared by workflow code and every agent adapter."

  defmodule Probe do
    @moduledoc false
    @enforce_keys [:adapter, :available?, :authenticated?, :status]
    defstruct [:adapter, :path, :version, :available?, :authenticated?, :status]
    @type t :: %__MODULE__{}
  end

  defmodule Capabilities do
    @moduledoc false
    @enforce_keys [
      :structured_output?,
      :native_resume?,
      :cancellation?,
      :usage?,
      :mcp?,
      :permission_modes,
      :model_discovery?,
      :instruction_files,
      :skill_directories
    ]
    defstruct @enforce_keys
    @type t :: %__MODULE__{}
  end

  defmodule EffectiveGrant do
    @moduledoc false
    @enforce_keys [:requested, :enforced, :unenforced]
    defstruct @enforce_keys
    @type t :: %__MODULE__{}
  end

  defmodule StageRequest do
    @moduledoc false
    @enforce_keys [
      :project_id,
      :board_id,
      :task_id,
      :run_id,
      :stage_key,
      :attempt_id,
      :objective,
      :worktree_path,
      :run_dir,
      :requested_model,
      :grant,
      :correlation_id,
      :idempotency_key
    ]
    defstruct @enforce_keys ++
                [
                  artifacts: [],
                  knowledge: [],
                  plugins: [],
                  required_output_schema: %{}
                ]

    @type t :: %__MODULE__{}
  end

  defmodule Session do
    @moduledoc false
    @enforce_keys [:adapter, :session_id, :requested_model, :effective_grant, :state]
    defstruct @enforce_keys ++ [:external_session_id, :actual_model, :process]
    @type t :: %__MODULE__{}
  end

  defmodule Event do
    @moduledoc false
    @enforce_keys [:event_id, :sequence, :type, :public_summary, :metadata, :trust]
    defstruct @enforce_keys
    @type t :: %__MODULE__{}
  end

  defmodule Usage do
    @moduledoc false
    @enforce_keys [:source, :confidence]
    defstruct @enforce_keys ++
                [
                  :input_tokens,
                  :output_tokens,
                  :cache_read_tokens,
                  :cache_write_tokens,
                  :cost_micros,
                  :currency
                ]

    @type t :: %__MODULE__{}

    def unavailable, do: %__MODULE__{source: "unavailable", confidence: "unavailable"}
  end

  defmodule ContinuationPackage do
    @moduledoc false
    alias Cuckoding.Adapters.Types.Error

    @enforce_keys [
      :run_id,
      :stage_key,
      :attempt_id,
      :task_revision,
      :spec,
      :summary,
      :artifact_hashes
    ]
    defstruct @enforce_keys ++ [completed_checks: [], open_findings: [], diff_summary: ""]
    @type t :: %__MODULE__{}

    def build(attributes, maximum_bytes \\ 65_536) do
      package = struct!(__MODULE__, attributes)

      if byte_size(Jason.encode!(Map.from_struct(package))) <= maximum_bytes,
        do: {:ok, package},
        else: {:error, Error.new(:continuation_too_large, :capability, false)}
    end
  end

  defmodule Error do
    @moduledoc false
    @enforce_keys [:code, :category, :retryable?]
    defstruct @enforce_keys ++ [:detail]
    @type t :: %__MODULE__{}

    def new(code, category, retryable?, detail \\ nil),
      do: %__MODULE__{code: code, category: category, retryable?: retryable?, detail: detail}
  end
end

defmodule Cuckoding.Adapters.EventStream do
  @moduledoc "Normalizes ordered provider events and removes exact duplicate event IDs."

  def normalize(adapter, provider_events, options \\ []) when is_list(provider_events) do
    provider_events
    |> Enum.sort_by(&sequence/1)
    |> Enum.reduce_while({:ok, {MapSet.new(), []}}, fn provider_event, {:ok, {seen, events}} ->
      case adapter.decode_event(provider_event, options) do
        {:ok, event} -> collect(event, seen, events)
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, {_seen, events}} -> {:ok, Enum.reverse(events)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp collect(event, seen, events) do
    if MapSet.member?(seen, event.event_id),
      do: {:cont, {:ok, {seen, events}}},
      else: {:cont, {:ok, {MapSet.put(seen, event.event_id), [event | events]}}}
  end

  defp sequence(%{"sequence" => sequence}) when is_integer(sequence), do: sequence
  defp sequence(_event), do: 9_223_372_036_854_775_807
end

defmodule Cuckoding.Adapters.FakeAdapter do
  @moduledoc "Deterministic adapter used by workflow and conformance tests."
  @behaviour Cuckoding.Adapters.AgentAdapter

  alias Cuckoding.Adapters.Types
  alias Cuckoding.Identifier
  alias Cuckoding.Security.Redactor

  @event_types ~w(session.started session.heartbeat session.completed session.failed activity.summary tool.requested tool.started tool.completed tool.denied artifact.created finding.created checkpoint.created usage.reported rate_limited approval.requested error.observed knowledge.cited)

  @impl true
  def probe(options), do: result(:probe, options, fn -> {:ok, default_probe(options)} end)

  @impl true
  def capabilities(options),
    do: result(:capabilities, options, fn -> {:ok, default_capabilities()} end)

  @impl true
  def render_config(%Types.StageRequest{} = request, options) do
    result(:render_config, options, fn -> write_config(request) end)
  end

  @impl true
  def start(%Types.StageRequest{} = request, options) do
    result(:start, options, fn ->
      {:ok,
       %Types.Session{
         adapter: "fake",
         session_id: Identifier.generate(),
         external_session_id: Keyword.get(options, :external_session_id, "fake-session"),
         requested_model: request.requested_model,
         actual_model: Keyword.get(options, :actual_model),
         effective_grant: effective_grant(request.grant),
         state: "running",
         process: Keyword.get(options, :process)
       }}
    end)
  end

  @impl true
  def send(%Types.Session{}, input, options) when is_map(input) do
    result(:send, options, fn ->
      decode_event(
        %{
          "event_id" => Identifier.generate(),
          "sequence" => Keyword.get(options, :sequence, 1),
          "type" => "activity.summary",
          "summary" => Map.get(input, "summary", "Fake follow-up accepted"),
          "metadata" => Map.drop(input, ["summary"])
        },
        options
      )
    end)
  end

  @impl true
  def pause(%Types.Session{} = session, options) do
    result(:pause, options, fn ->
      {:ok, %{"session_id" => session.session_id, "summary" => "Fake checkpoint"}}
    end)
  end

  @impl true
  def resume(subject, checkpoint, options) when is_map(checkpoint) do
    result(:resume, options, fn -> {:ok, resumed_session(subject, options)} end)
  end

  @impl true
  def recover(%Types.Session{} = session, inspection, options) when is_map(inspection) do
    result(:recover, options, fn ->
      if inspection[:process] == :matching and inspection[:session] == :available,
        do: {:ok, session},
        else: resume(session, %{"reason" => "sleep_gap"}, options)
    end)
  end

  @impl true
  def cancel(%Types.Session{} = session, options),
    do: result(:cancel, options, fn -> {:ok, %{session | state: "cancelled"}} end)

  @impl true
  def inspect(%Types.Session{} = session, options),
    do: result(:inspect, options, fn -> {:ok, Map.from_struct(session)} end)

  @impl true
  def decode_event(provider_event, options) when is_map(provider_event) do
    result(:decode_event, options, fn -> decode(provider_event, options) end)
  end

  def decode_event(_provider_event, _options),
    do: {:error, Types.Error.new(:malformed_event, :malformed_output, false)}

  @impl true
  def collect_usage(%Types.Session{}, options) do
    result(:collect_usage, options, fn ->
      case Keyword.get(options, :usage) do
        nil -> {:ok, Types.Usage.unavailable()}
        usage -> {:ok, struct!(Types.Usage, usage)}
      end
    end)
  end

  defp write_config(request) do
    agent_dir = Path.join(request.run_dir, "agent")
    path = Path.join(agent_dir, "fake-adapter.json")
    temporary = path <> ".#{Identifier.generate()}.tmp"

    with :ok <- confined_agent_dir?(agent_dir, request.run_dir),
         :ok <- prepare_agent_dir(agent_dir),
         grant = effective_grant(request.grant),
         config = %{
           "objective" => request.objective,
           "grant" => Map.from_struct(grant),
           "knowledge" => request.knowledge,
           "plugins" => request.plugins,
           "required_output_schema" => request.required_output_schema
         },
         :ok <- File.write(temporary, Jason.encode_to_iodata!(config), [:exclusive]),
         :ok <- File.chmod(temporary, 0o600),
         :ok <- File.rename(temporary, path) do
      {:ok, grant}
    else
      {:error, reason} -> {:error, Types.Error.new(reason, :capability, false)}
    end
  end

  defp confined_agent_dir?(agent_dir, run_dir) do
    if Path.expand(agent_dir) == Path.join(Path.expand(run_dir), "agent"),
      do: :ok,
      else: {:error, :config_path_escape}
  end

  defp prepare_agent_dir(agent_dir) do
    with :ok <- reject_symlink(agent_dir),
         :ok <- File.mkdir_p(agent_dir) do
      reject_symlink(agent_dir)
    end
  end

  defp reject_symlink(path) do
    case File.lstat(path) do
      {:ok, %{type: :symlink}} -> {:error, :config_path_symlink}
      {:ok, %{type: :directory}} -> :ok
      {:ok, _other} -> {:error, :config_path_not_directory}
      {:error, :enoent} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp effective_grant(requested) do
    enforced = Map.take(requested, ["tools", "paths", "approval_mode"])
    unenforced = Map.take(requested, ["network", "resource_limits"])
    %Types.EffectiveGrant{requested: requested, enforced: enforced, unenforced: unenforced}
  end

  defp decode(provider_event, options) do
    with event_id when is_binary(event_id) <- provider_event["event_id"],
         sequence when is_integer(sequence) and sequence >= 0 <- provider_event["sequence"],
         type when type in @event_types <- provider_event["type"],
         summary when is_binary(summary) <- provider_event["summary"],
         metadata when is_map(metadata) <- Map.get(provider_event, "metadata", %{}) do
      {:ok,
       %Types.Event{
         event_id: event_id,
         sequence: sequence,
         type: type,
         public_summary: Redactor.redact(summary, Keyword.get(options, :redact, [])),
         metadata: Redactor.redact(metadata, Keyword.get(options, :redact, [])),
         trust: :untrusted
       }}
    else
      type when is_binary(type) and type not in @event_types ->
        {:error, Types.Error.new(:unknown_event, :malformed_output, false)}

      _other ->
        {:error, Types.Error.new(:malformed_event, :malformed_output, false)}
    end
  end

  defp resumed_session(%Types.Session{} = session, _options), do: %{session | state: "running"}

  defp resumed_session(%Types.ContinuationPackage{} = package, options) do
    %Types.Session{
      adapter: "fake",
      session_id: Identifier.generate(),
      external_session_id: nil,
      requested_model: Keyword.get(options, :requested_model),
      actual_model: nil,
      effective_grant: %Types.EffectiveGrant{requested: %{}, enforced: %{}, unenforced: %{}},
      state: "running",
      process: %{"continuation_attempt_id" => package.attempt_id}
    }
  end

  defp default_probe(options) do
    %Types.Probe{
      adapter: "fake",
      path: Keyword.get(options, :path, "/usr/bin/false"),
      version: Keyword.get(options, :version, "test"),
      available?: true,
      authenticated?: true,
      status: "healthy"
    }
  end

  defp default_capabilities do
    %Types.Capabilities{
      structured_output?: true,
      native_resume?: true,
      cancellation?: true,
      usage?: true,
      mcp?: true,
      permission_modes: ["default", "plan"],
      model_discovery?: false,
      instruction_files: ["FAKE.md"],
      skill_directories: ["agent/skills"]
    }
  end

  defp result(operation, options, callback) do
    case get_in(Keyword.get(options, :failures, %{}), [operation]) do
      nil -> callback.()
      reason -> {:error, Types.Error.new(reason, category(reason), retryable?(reason))}
    end
  end

  defp category(reason) when reason in [:timeout, :rate_limited, :crashed], do: :transient
  defp category(:cancelled), do: :cancelled
  defp category(_reason), do: :provider

  defp retryable?(reason), do: reason in [:timeout, :rate_limited, :crashed]
end
