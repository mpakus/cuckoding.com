defmodule Cuckoding.NativeFolder do
  @moduledoc false
  alias Cuckoding.Foundation

  def choose(command) do
    started = System.monotonic_time(:millisecond)
    result = run(command, started)
    Map.put(result, "elapsed_ms", System.monotonic_time(:millisecond) - started)
  end

  defp run(command, started) do
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
        args: ["--choose-arena-folder"],
        env: env,
        cd: root
      ])

    try do
      collect(port, command, started, "")
    after
      if Port.info(port), do: Port.close(port)
    end
  rescue
    _ -> %{"status" => "unavailable"}
  end

  defp collect(port, command, started, bytes) do
    cond do
      not Foundation.probe_active?(command) ->
        cancel(port)

      System.monotonic_time(:millisecond) - started > 125_000 ->
        %{"status" => "timeout"}

      byte_size(bytes) > 8192 ->
        %{"status" => "unavailable"}

      true ->
        receive do
          {^port, {:data, chunk}} -> collect(port, command, started, bytes <> chunk)
          {^port, {:exit_status, 0}} -> decode(bytes)
          {^port, {:exit_status, _}} -> %{"status" => "unavailable"}
        after
          100 -> collect(port, command, started, bytes)
        end
    end
  end

  defp cancel(port) do
    Port.command(port, "\n")
    wait_for_exit(port, System.monotonic_time(:millisecond) + 3_000)
  end

  defp wait_for_exit(port, deadline) do
    remaining = max(0, deadline - System.monotonic_time(:millisecond))

    receive do
      {^port, {:exit_status, _}} -> %{"status" => "cancelled"}
      {^port, {:data, _}} -> wait_for_exit(port, deadline)
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
