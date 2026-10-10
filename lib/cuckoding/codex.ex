defmodule Cuckoding.AgentAdapter do
  @moduledoc "Private profile operations and restricted diagnostic/brief turns; no repository tasks."
  @callback probe(map(), binary(), (-> boolean())) :: map()
  @callback inspect_connection(map(), binary(), (-> boolean())) :: map()
  @callback check_model(map(), binary(), binary(), binary(), binary(), (-> boolean())) :: map()
  @callback plan(map(), binary(), binary(), map(), (-> boolean())) :: map()
  @callback authorize(map(), binary(), :login | :logout, (-> boolean()), (binary() -> any())) ::
              map()
end

defmodule Cuckoding.Codex do
  @moduledoc "Version readiness and fixed private-profile operations."
  @behaviour Cuckoding.AgentAdapter
  import Bitwise
  @verified_versions ~w(0.146.0 0.162.0-alpha.2 0.162.0-alpha.17.2)
  @errors ~w(launch_failed timeout cancelled invalid_output executable_changed helper_unavailable)
  @connection_errors @errors ++
                       ~w(connection_lost provider_error unexpected_message profile_mismatch unsupported_profile unsafe_profile profile_busy invalid_login login_failed logout_unconfirmed cleanup_uncertain)

  @model_errors @connection_errors ++
                  ~w(not_connected model_unavailable model_mismatch unsupported_grant invalid_response unexpected_tool turn_failed interrupted)

  # Ephemeral presentation only. The dispatcher owns this table; SQLite owns lifecycle.
  def init_login_links, do: :ets.new(:cuckoding_login_link, [:named_table, :protected, :set])
  def clear_login_link, do: :ets.delete_all_objects(:cuckoding_login_link)

  def put_login_link(id, url, kind \\ "codex") do
    if valid_login_url?(url, kind) do
      :ets.insert(:cuckoding_login_link, {id, url, System.system_time(:second) + 600})
    end
  end

  def login_link(id) do
    case :ets.lookup(:cuckoding_login_link, id) do
      [{^id, url, expires}] -> if expires > System.system_time(:second), do: url
      _ -> nil
    end
  rescue
    ArgumentError -> nil
  end

  def valid_login_url?(url, kind \\ "codex")

  def valid_login_url?(url, kind) when is_binary(url) and byte_size(url) in 1..8192 do
    uri = URI.parse(url)

    login_provider?(uri, kind) and uri.scheme == "https" and uri.port == 443 and
      is_nil(uri.userinfo) and
      is_nil(uri.fragment) and
      not Regex.match?(~r/[\x00-\x20\x7f\\]/, url)
  end

  def valid_login_url?(_, _), do: false

  defp login_provider?(uri, "codex"),
    do:
      uri.host in ["auth.openai.com", "chatgpt.com"] and
        uri.path in ["/oauth/authorize", "/auth/authorize"]

  defp login_provider?(uri, "cursor"),
    do: uri.host == "cursor.com" and uri.path == "/loginDeepControl"

  defp login_provider?(_, _), do: false

  # Metadata only; never execute a path while editing or discovering it.
  # sobelow_skip ["Traversal.FileModule"]
  def executable(path) when is_binary(path) and byte_size(path) in 1..4096 do
    with true <- Path.type(path) == :absolute and not String.contains?(path, ["\n", "\r", <<0>>]),
         true <- Path.expand(path) == path,
         {:ok, stat} <- File.stat(path, time: :posix),
         true <- stat.type == :regular and band(stat.mode, 0o111) != 0 do
      {:ok,
       %{
         "path" => path,
         "inode" => stat.inode,
         "device" => stat.major_device,
         "size" => stat.size,
         "modified" => stat.mtime,
         "changed" => stat.ctime
       }}
    else
      _ -> {:error, :invalid_executable}
    end
  end

  def executable(_), do: {:error, :invalid_executable}

  @impl true
  def probe(identity, directory, active?) do
    observe(identity, directory, active?, "--probe-codex", &normalize/1, 1024, 8_000)
  end

  @impl true
  def inspect_connection(identity, directory, active?) do
    observe(
      identity,
      directory,
      active?,
      "--inspect-codex",
      &normalize_connection/1,
      524_288,
      13_000
    )
  end

  @impl true
  def authorize(identity, directory, operation, active?, progress)
      when operation in [:login, :logout] do
    observe(
      identity,
      directory,
      active?,
      "--#{operation}-codex",
      &normalize_connection/1,
      524_288,
      if(operation == :login, do: 615_000, else: 13_000),
      progress: progress
    )
  end

  @impl true
  def check_model(identity, profile, scratch, model, effort, active?) do
    observe(
      identity,
      profile,
      active?,
      "--check-codex-model",
      &normalize_model_check/1,
      1024,
      125_000,
      progress: :no_progress,
      args: [scratch, model, effort]
    )
  end

  @impl true
  def plan(identity, profile, scratch, request, active?) do
    observe(
      identity,
      profile,
      active?,
      "--plan-codex-brief",
      &Cuckoding.Planning.normalize/1,
      65_536,
      125_000,
      progress: :no_progress,
      args: [scratch, request["model"], request["effort"]],
      input:
        Jason.encode!(Map.take(request, ~w(request_id brief instructions documents contract))) <>
          "\n"
    )
  end

  def observe(
        identity,
        directory,
        active?,
        operation,
        normalize,
        limit,
        timeout,
        options \\ []
      ) do
    helper = Application.get_env(:cuckoding, :native_helper)

    cond do
      executable(identity["path"]) != {:ok, identity} ->
        %{"status" => "executable_changed"}

      not is_binary(helper) ->
        %{"status" => "helper_unavailable"}

      true ->
        run(
          helper,
          [operation, identity["path"], directory] ++ Keyword.get(options, :args, []),
          active?,
          normalize,
          limit,
          timeout,
          options
        )
    end
  end

  # Only the app-owned native helper gets a Port. It clears the provider environment,
  # owns the process group and returns fixed public fields, never raw provider output.
  defp run(helper, args, active?, normalize, limit, timeout, options) do
    progress = Keyword.get(options, :progress)

    port =
      Port.open({:spawn_executable, helper}, [
        :binary,
        :exit_status,
        args: args
      ])

    try do
      if input = options[:input], do: Port.command(port, input)
      deadline = System.monotonic_time(:millisecond) + timeout

      if progress do
        auth_collect(
          port,
          %{
            normalize: normalize,
            login_kind: Keyword.get(options, :login_kind, "codex"),
            buffer: "",
            bytes: 0,
            result: nil,
            prompted: false,
            deadline: deadline,
            cancelling: false
          },
          active?,
          progress
        )
      else
        collect(port, "", deadline, active?, normalize, limit)
      end
    after
      if Port.info(port), do: Port.close(port)
    end
  rescue
    ArgumentError -> %{"status" => "launch_failed"}
    ErlangError -> %{"status" => "launch_failed"}
  end

  defp auth_collect(port, state, active?, progress) do
    now = System.monotonic_time(:millisecond)

    state =
      if not state.cancelling and not active?.() do
        Port.command(port, "cancel\n")
        %{state | cancelling: true, deadline: min(state.deadline, now + 3_000)}
      else
        state
      end

    if now >= state.deadline do
      %{"status" => "cleanup_uncertain"}
    else
      auth_receive(port, state, active?, progress)
    end
  end

  defp auth_receive(port, state, active?, progress) do
    receive do
      {^port, {:data, chunk}} ->
        case auth_frames(state, chunk, progress) do
          {:ok, next} -> auth_collect(port, next, active?, progress)
          :error -> %{"status" => "invalid_output"}
        end

      {^port, {:exit_status, 0}} ->
        if state.buffer == "" and state.result,
          do: state.result,
          else: %{"status" => "invalid_output"}

      {^port, {:exit_status, _}} ->
        %{"status" => "cleanup_uncertain"}
    after
      50 -> auth_collect(port, state, active?, progress)
    end
  end

  defp auth_frames(state, chunk, progress) do
    bytes = state.bytes + byte_size(chunk)

    if bytes > 524_288 do
      :error
    else
      lines = String.split(state.buffer <> chunk, "\n")
      pending = List.last(lines)

      Enum.reduce_while(
        Enum.drop(lines, -1),
        {:ok, %{state | bytes: bytes, buffer: pending}},
        fn line, {:ok, state} -> reduce_auth_frame(state, line, progress) end
      )
    end
  end

  defp reduce_auth_frame(state, line, progress) do
    case auth_frame(state, line, progress) do
      {:ok, next} -> {:cont, {:ok, next}}
      :error -> {:halt, :error}
    end
  end

  defp publish_progress(%{cancelling: true}, _, _), do: :ok
  defp publish_progress(_, url, progress), do: progress.(url)

  defp auth_frame(%{result: nil} = state, line, progress) do
    case Jason.decode(line) do
      {:ok, %{"status" => "awaiting_login", "auth_url" => url}} ->
        if is_function(progress) and not state.prompted and
             valid_login_url?(url, state.login_kind) do
          publish_progress(state, url, progress)
          {:ok, %{state | prompted: true}}
        else
          :error
        end

      _ ->
        {:ok, %{state | result: state.normalize.(line)}}
    end
  end

  defp auth_frame(_, _, _), do: :error

  defp collect(port, data, deadline, active?, normalize, limit) do
    cond do
      byte_size(data) > limit -> %{"status" => "invalid_output"}
      not active?.() -> %{"status" => "cancelled"}
      System.monotonic_time(:millisecond) > deadline -> %{"status" => "timeout"}
      true -> receive_output(port, data, deadline, active?, normalize, limit)
    end
  end

  defp receive_output(port, data, deadline, active?, normalize, limit) do
    receive do
      {^port, {:data, chunk}} -> collect(port, data <> chunk, deadline, active?, normalize, limit)
      {^port, {:exit_status, 0}} -> normalize.(data)
      {^port, {:exit_status, _}} -> %{"status" => "launch_failed"}
    after
      50 -> collect(port, data, deadline, active?, normalize, limit)
    end
  end

  def normalize(data) when is_binary(data) and byte_size(data) <= 1024 do
    case Jason.decode(data) do
      {:ok, %{"status" => "observed", "version" => version} = result} ->
        if is_binary(version) and
             Regex.match?(
               ~r/\A\d{1,5}\.\d{1,5}\.\d{1,5}(?:-alpha\.\d{1,5}(?:\.\d{1,5})?)?\z/,
               version
             ) do
          result
          |> public_fields()
          |> Map.merge(%{
            "status" => if(version in @verified_versions, do: "supported", else: "unsupported"),
            "version" => version
          })
        else
          %{"status" => "invalid_output"}
        end

      {:ok, %{"status" => status} = result} when status in @errors ->
        Map.put(public_fields(result), "status", status)

      _ ->
        %{"status" => "invalid_output"}
    end
  end

  def normalize(_), do: %{"status" => "invalid_output"}

  def normalize_connection(data) when is_binary(data) and byte_size(data) <= 524_288 do
    case Jason.decode(data) do
      {:ok,
       %{"status" => "checked", "authorization" => auth, "catalog_status" => catalog} = result} ->
        normalized =
          result
          |> Map.take(~w(status authorization catalog_status))
          |> Map.merge(public_fields(result))

        case {auth, catalog} do
          {auth, "not_requested"} when auth in ~w(not_connected unsupported_account) ->
            normalized

          {"chatgpt", "failed"} ->
            Map.put(normalized, "catalog_error", "refresh_failed")

          {"chatgpt", "fresh"} ->
            normalize_models(normalized, result["models"])

          _ ->
            %{"status" => "invalid_output"}
        end

      {:ok, %{"status" => status} = result} when status in @connection_errors ->
        Map.put(public_fields(result), "status", status)

      _ ->
        %{"status" => "invalid_output"}
    end
  end

  def normalize_connection(_), do: %{"status" => "invalid_output"}

  def normalize_model_check(data) when is_binary(data) and byte_size(data) <= 1024 do
    case Jason.decode(data) do
      {:ok, %{"status" => "passed", "grant" => "scratch-read-only-v1"} = result} ->
        if Enum.all?(~w(requested_model observed_model effort), &identifier?(result[&1])) and
             match?({:ok, _}, Ecto.UUID.cast(result["thread_id"])) and
             match?({:ok, _}, Ecto.UUID.cast(result["turn_id"])) do
          result
          |> Map.take(~w(status requested_model observed_model effort thread_id turn_id grant))
          |> Map.merge(public_fields(result))
        else
          %{"status" => "invalid_output"}
        end

      {:ok, %{"status" => status} = result} when status in @model_errors ->
        Map.put(public_fields(result), "status", status)

      _ ->
        %{"status" => "invalid_output"}
    end
  end

  def normalize_model_check(_), do: %{"status" => "invalid_output"}

  defp normalize_models(result, models) when is_list(models) and length(models) <= 128 do
    if Enum.all?(models, &valid_model?/1) and Enum.uniq_by(models, & &1["id"]) == models do
      Map.put(
        result,
        "models",
        Enum.map(
          models,
          &Map.take(&1, ~w(id model name efforts default_effort input_modalities default hidden))
        )
      )
    else
      Map.merge(result, %{"catalog_status" => "failed", "catalog_error" => "invalid_catalog"})
    end
  end

  defp normalize_models(result, _),
    do: Map.merge(result, %{"catalog_status" => "failed", "catalog_error" => "invalid_catalog"})

  defp valid_model?(
         %{
           "id" => id,
           "model" => model,
           "name" => name,
           "efforts" => efforts,
           "default_effort" => default,
           "input_modalities" => modalities,
           "default" => selected
         } = row
       ) do
    identifier?(id) and identifier?(model) and label?(name) and
      efforts?(efforts, default) and modalities?(modalities) and is_boolean(selected) and
      is_boolean(Map.get(row, "hidden", false))
  end

  defp valid_model?(_), do: false

  defp label?(name),
    do:
      is_binary(name) and byte_size(name) in 1..128 and String.valid?(name) and
        not Regex.match?(~r/[\x00-\x1f\x7f]/, name)

  defp efforts?(efforts, default),
    do:
      is_list(efforts) and length(efforts) in 1..16 and Enum.all?(efforts, &identifier?/1) and
        default in efforts

  defp modalities?(modalities),
    do:
      is_list(modalities) and length(modalities) <= 3 and
        Enum.all?(modalities, &(&1 in ~w(text image audio)))

  defp identifier?(value),
    do:
      is_binary(value) and byte_size(value) in 1..128 and
        Regex.match?(~r/\A[a-zA-Z0-9._\/-]+\z/, value)

  def public_fields(result) do
    for key <- ~w(pid spawned_at_ms elapsed_ms),
        value = result[key],
        is_integer(value) and value >= 0 and value < 10_000_000_000_000,
        into: %{},
        do: {key, value}
  end
end
