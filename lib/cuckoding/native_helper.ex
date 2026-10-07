defmodule Cuckoding.NativeHelper do
  @moduledoc false
  alias Cuckoding.Foundation

  def choose_folder(command), do: request(command, ["--choose-arena-folder"], 125_000, &decode/1)

  def request(command, args, timeout, decode, limit \\ 8192) do
    started = System.monotonic_time(:millisecond)
    previous = Process.flag(:trap_exit, true)

    try do
      result = run(command, args, started + timeout, decode, limit)
      Map.put(result, "elapsed_ms", System.monotonic_time(:millisecond) - started)
    after
      Process.flag(:trap_exit, previous)
    end
  end

  defp run(command, args, deadline, decode, limit) do
    helper = Application.fetch_env!(:cuckoding, :native_helper)
    {:ok, _} = Cuckoding.Codex.executable(helper)
    root = Application.fetch_env!(:cuckoding, :data_dir)

    cleared =
      System.get_env()
      |> Map.drop(~w(HOME PATH LANG TZ))
      |> Enum.map(fn {key, _} -> {String.to_charlist(key), false} end)

    env =
      cleared ++
        [
          {~c"HOME", String.to_charlist(Path.join(root, "runtime-home"))},
          {~c"PATH", ~c"/usr/bin:/bin:/usr/sbin:/sbin"},
          {~c"LANG", ~c"en_US.UTF-8"},
          {~c"TZ", ~c"UTC"}
        ]

    port =
      Port.open({:spawn_executable, helper}, [
        :binary,
        :exit_status,
        args: args,
        env: env,
        cd: root
      ])

    try do
      collect(port, command, deadline, decode, limit, "")
    after
      if Port.info(port), do: Port.close(port)

      receive do
        {:EXIT, ^port, _} -> :ok
      after
        0 -> :ok
      end
    end
  rescue
    _ -> %{"status" => "unavailable"}
  end

  defp collect(port, command, deadline, decode, limit, bytes) do
    cond do
      not Foundation.probe_active?(command) ->
        cancel(port)

      System.monotonic_time(:millisecond) > deadline ->
        halt(port, "timeout")

      byte_size(bytes) > limit ->
        halt(port, "unavailable")

      true ->
        receive do
          {^port, {:data, chunk}} ->
            collect(port, command, deadline, decode, limit, bytes <> chunk)

          {^port, {:exit_status, 0}} ->
            decode.(bytes)

          {^port, {:exit_status, _}} ->
            %{"status" => "cleanup_uncertain"}

          {:EXIT, ^port, _} ->
            %{"status" => "cleanup_uncertain"}
        after
          100 -> collect(port, command, deadline, decode, limit, bytes)
        end
    end
  end

  defp halt(port, status) do
    case cancel(port) do
      %{"status" => "cancelled"} -> %{"status" => status}
      result -> result
    end
  end

  defp cancel(port) do
    Port.command(port, "\n")
    wait_for_exit(port, System.monotonic_time(:millisecond) + 3_000)
  rescue
    ArgumentError -> %{"status" => "cleanup_uncertain"}
  end

  defp wait_for_exit(port, deadline) do
    remaining = max(0, deadline - System.monotonic_time(:millisecond))

    receive do
      {^port, {:exit_status, 0}} -> %{"status" => "cancelled"}
      {^port, {:exit_status, _}} -> %{"status" => "cleanup_uncertain"}
      {^port, {:data, _}} -> wait_for_exit(port, deadline)
      {:EXIT, ^port, _} -> %{"status" => "cleanup_uncertain"}
    after
      remaining -> %{"status" => "cleanup_uncertain"}
    end
  end

  defp decode(bytes) do
    case Jason.decode(bytes) do
      {:ok, %{"status" => status} = result}
      when status in ~w(selected cancelled timeout invalid_folder) ->
        Map.take(result, ~w(status path))

      _ ->
        %{"status" => "unavailable"}
    end
  end
end
