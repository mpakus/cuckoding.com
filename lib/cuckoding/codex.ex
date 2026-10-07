defmodule Cuckoding.AgentAdapter do
  @moduledoc "Implemented adapter surface; authorization and turns are not enabled yet."
  @callback probe(map(), binary(), (-> boolean())) :: map()
end

defmodule Cuckoding.Codex do
  @moduledoc "Explicit version readiness, separate from account authorization."
  @behaviour Cuckoding.AgentAdapter
  import Bitwise
  @verified_version "0.146.0"
  @errors ~w(launch_failed timeout cancelled invalid_output executable_changed helper_unavailable)

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
    helper = Application.get_env(:cuckoding, :native_helper)

    cond do
      executable(identity["path"]) != {:ok, identity} ->
        %{"status" => "executable_changed"}

      not is_binary(helper) ->
        %{"status" => "helper_unavailable"}

      true ->
        run(helper, identity["path"], directory, active?)
    end
  end

  # Only the app-owned native helper gets a Port. It clears the provider environment,
  # owns the process group and returns fixed public fields, never raw provider output.
  defp run(helper, path, directory, active?) do
    port =
      Port.open({:spawn_executable, helper}, [
        :binary,
        :exit_status,
        args: ["--probe-codex", path, directory]
      ])

    try do
      collect(port, "", System.monotonic_time(:millisecond) + 8_000, active?)
    after
      if Port.info(port), do: Port.close(port)
    end
  rescue
    ArgumentError -> %{"status" => "launch_failed"}
    ErlangError -> %{"status" => "launch_failed"}
  end

  defp collect(port, data, deadline, active?) do
    cond do
      byte_size(data) > 1024 -> %{"status" => "invalid_output"}
      not active?.() -> %{"status" => "cancelled"}
      System.monotonic_time(:millisecond) > deadline -> %{"status" => "timeout"}
      true -> receive_output(port, data, deadline, active?)
    end
  end

  defp receive_output(port, data, deadline, active?) do
    receive do
      {^port, {:data, chunk}} -> collect(port, data <> chunk, deadline, active?)
      {^port, {:exit_status, 0}} -> normalize(data)
      {^port, {:exit_status, _}} -> %{"status" => "launch_failed"}
    after
      50 -> collect(port, data, deadline, active?)
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

  defp public_fields(result) do
    for key <- ~w(pid spawned_at_ms elapsed_ms),
        value = result[key],
        is_integer(value) and value >= 0 and value < 10_000_000_000_000,
        into: %{},
        do: {key, value}
  end
end
