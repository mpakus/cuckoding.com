defmodule Cuckoding.NativeHelper do
  @moduledoc false
  alias Cuckoding.Foundation

  def choose_folder(command), do: request(command, ["--choose-arena-folder"], 125_000, &decode/1)

  def request(command, args, timeout, decode, limit \\ 8192, options \\ []) do
    started = System.monotonic_time(:millisecond)
    previous = Process.flag(:trap_exit, true)

    try do
      active? = Keyword.get(options, :active?, fn -> Foundation.probe_active?(command) end)

      result =
        if active?.(),
          do: run(active?, args, started + timeout, decode, limit, options[:input]),
          else: %{"status" => "cancelled", "cleanup_verified" => true}

      Map.put(result, "elapsed_ms", System.monotonic_time(:millisecond) - started)
    after
      Process.flag(:trap_exit, previous)
    end
  end

  defp run(active?, args, deadline, decode, limit, input) do
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
      if active?.() do
        if input, do: Port.command(port, input <> "\n")
        collect(port, active?, deadline, decode, limit, "")
      else
        cancel(port, decode, limit, "")
      end
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

  defp collect(port, active?, deadline, decode, limit, bytes) do
    cond do
      not active?.() ->
        cancel(port, decode, limit, bytes)

      System.monotonic_time(:millisecond) > deadline ->
        halt(port, "timeout", decode, limit, bytes)

      byte_size(bytes) > limit ->
        halt(port, "unavailable", decode, limit, bytes)

      true ->
        receive do
          {^port, {:data, chunk}} ->
            collect(port, active?, deadline, decode, limit, bytes <> chunk)

          {^port, {:exit_status, 0}} ->
            decode.(bytes)

          {^port, {:exit_status, _}} ->
            %{"status" => "cleanup_uncertain"}

          {:EXIT, ^port, _} ->
            %{"status" => "cleanup_uncertain"}
        after
          100 -> collect(port, active?, deadline, decode, limit, bytes)
        end
    end
  end

  defp halt(port, status, decode, limit, bytes) do
    case cancel(port, decode, limit, bytes) do
      %{"status" => "cancelled", "cleanup_verified" => true} = result ->
        Map.put(result, "status", status)

      result ->
        result
    end
  end

  defp cancel(port, decode, limit, bytes) do
    Port.command(port, "\n")
    wait_for_exit(port, System.monotonic_time(:millisecond) + 5_000, decode, limit, bytes)
  rescue
    ArgumentError -> %{"status" => "cleanup_uncertain"}
  end

  defp wait_for_exit(port, deadline, decode, limit, bytes) do
    remaining = max(0, deadline - System.monotonic_time(:millisecond))

    receive do
      {^port, {:exit_status, 0}} ->
        cancellation_receipt(bytes, decode, limit)

      {^port, {:exit_status, _}} ->
        %{"status" => "cleanup_uncertain"}

      {^port, {:data, chunk}} ->
        bytes = if byte_size(bytes) <= limit, do: bytes <> chunk, else: bytes
        wait_for_exit(port, deadline, decode, limit, bytes)

      {:EXIT, ^port, _} ->
        %{"status" => "cleanup_uncertain"}
    after
      remaining -> %{"status" => "cleanup_uncertain"}
    end
  end

  defp cancellation_receipt(bytes, decode, limit) when byte_size(bytes) <= limit do
    case decode.(bytes) do
      %{"cleanup_verified" => false} = result ->
        Map.put(result, "status", "cleanup_uncertain")

      %{"status" => "cancelled"} = result ->
        Map.put(result, "cleanup_verified", true)

      %{"status" => status} when status in ~w(unavailable invalid_output) ->
        %{"status" => "cleanup_uncertain"}

      result ->
        result
    end
  end

  defp cancellation_receipt(_, _, _), do: %{"status" => "cleanup_uncertain"}

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
