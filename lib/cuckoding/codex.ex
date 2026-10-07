defmodule Cuckoding.AgentAdapter do
  @moduledoc "Implemented adapter surface; login and turns are not enabled yet."
  @callback probe(map(), binary(), (-> boolean())) :: map()
  @callback inspect_connection(map(), binary(), (-> boolean())) :: map()
end

defmodule Cuckoding.Codex do
  @moduledoc "Version readiness and read-only private-profile inspection."
  @behaviour Cuckoding.AgentAdapter
  import Bitwise
  @verified_version "0.146.0"
  @errors ~w(launch_failed timeout cancelled invalid_output executable_changed helper_unavailable)
  @connection_errors @errors ++
                       ~w(connection_lost provider_error unexpected_message profile_mismatch unsupported_profile unsafe_profile)

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

  defp observe(identity, directory, active?, operation, normalize, limit, timeout) do
    helper = Application.get_env(:cuckoding, :native_helper)

    cond do
      executable(identity["path"]) != {:ok, identity} ->
        %{"status" => "executable_changed"}

      not is_binary(helper) ->
        %{"status" => "helper_unavailable"}

      true ->
        run(helper, [operation, identity["path"], directory], active?, normalize, limit, timeout)
    end
  end

  # Only the app-owned native helper gets a Port. It clears the provider environment,
  # owns the process group and returns fixed public fields, never raw provider output.
  defp run(helper, args, active?, normalize, limit, timeout) do
    port =
      Port.open({:spawn_executable, helper}, [
        :binary,
        :exit_status,
        args: args
      ])

    try do
      collect(port, "", System.monotonic_time(:millisecond) + timeout, active?, normalize, limit)
    after
      if Port.info(port), do: Port.close(port)
    end
  rescue
    ArgumentError -> %{"status" => "launch_failed"}
    ErlangError -> %{"status" => "launch_failed"}
  end

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
        if is_binary(version) and Regex.match?(~r/\A\d{1,5}\.\d{1,5}\.\d{1,5}\z/, version) do
          result
          |> public_fields()
          |> Map.merge(%{
            "status" => if(version == @verified_version, do: "supported", else: "unsupported"),
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

  defp normalize_models(result, models) when is_list(models) and length(models) <= 128 do
    if Enum.all?(models, &valid_model?/1) and Enum.uniq_by(models, & &1["id"]) == models do
      Map.put(
        result,
        "models",
        Enum.map(
          models,
          &Map.take(&1, ~w(id model name efforts default_effort input_modalities default))
        )
      )
    else
      Map.merge(result, %{"catalog_status" => "failed", "catalog_error" => "invalid_catalog"})
    end
  end

  defp normalize_models(result, _),
    do: Map.merge(result, %{"catalog_status" => "failed", "catalog_error" => "invalid_catalog"})

  defp valid_model?(%{
         "id" => id,
         "model" => model,
         "name" => name,
         "efforts" => efforts,
         "default_effort" => default,
         "input_modalities" => modalities,
         "default" => selected
       }) do
    identifier?(id) and identifier?(model) and label?(name) and
      efforts?(efforts, default) and modalities?(modalities) and is_boolean(selected)
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

  defp public_fields(result) do
    for key <- ~w(pid spawned_at_ms elapsed_ms),
        value = result[key],
        is_integer(value) and value >= 0 and value < 10_000_000_000_000,
        into: %{},
        do: {key, value}
  end
end
