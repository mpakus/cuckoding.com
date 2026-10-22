defmodule Cuckoding.BattleRepository do
  @moduledoc "Cancellable VM I/O queue; native ownership and durable receipts remain authoritative."
  @wait_ms 65_000

  def run(%{"device" => device, "inode" => inode}, active?, action)
      when is_integer(device) and device >= 0 and is_integer(inode) and inode > 0 do
    lock = {{__MODULE__, device, inode}, self()}
    acquire(lock, active?, action, System.monotonic_time(:millisecond) + @wait_ms)
  end

  defp acquire(lock, active?, action, deadline) do
    cond do
      not active?.() ->
        %{"status" => "cancelled", "cleanup_verified" => true}

      System.monotonic_time(:millisecond) >= deadline ->
        %{"status" => "repository_busy", "cleanup_verified" => true}

      :global.set_lock(lock, [node()], 0) ->
        try do
          if active?.(),
            do: action.(),
            else: %{"status" => "cancelled", "cleanup_verified" => true}
        after
          :global.del_lock(lock, [node()])
        end

      true ->
        Process.sleep(25)
        acquire(lock, active?, action, deadline)
    end
  end
end
