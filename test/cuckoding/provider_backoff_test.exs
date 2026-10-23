defmodule Cuckoding.ProviderBackoffTest do
  use ExUnit.Case, async: true
  alias Cuckoding.Battles.{Attempt, Backoff, Battle}

  defp attempt(reason, policy) do
    %Attempt{
      id: Ecto.UUID.generate(),
      result: %{"reason" => reason},
      request: %{"snapshot" => %{"provider_backoff" => policy}}
    }
  end

  defp waiting(attempt, wait) do
    %Battle{
      snapshot: attempt.request["snapshot"],
      state: "needs_attention",
      reason: attempt.result["reason"],
      context: %{"provider_backoff" => wait}
    }
  end

  test "overload jitter is bounded and retained; historical waits preserve their exact rules" do
    now = DateTime.utc_now()
    modern = attempt("provider_overloaded", Backoff.policy())
    assert Backoff.transient?(modern)

    for used <- 0..1 do
      wait = Backoff.schedule(modern, used, now)
      assert wait == Backoff.schedule(modern, used, now)
      assert wait["delay_seconds"] in if(used == 0, do: 5..7, else: 20..22)
      assert Backoff.pending?(waiting(modern, wait))
      {:ok, due, 0} = Backoff.due_at(waiting(modern, wait))
      assert DateTime.diff(due, now) == wait["delay_seconds"]
      refute Backoff.pending?(waiting(modern, Map.put(wait, "delay_seconds", 8)))
    end

    for policy <- ["automatic-provider-backoff-v1", Backoff.policy()] do
      legacy = attempt("connection_lost", policy)
      assert Backoff.transient?(legacy)

      for {used, delay} <- [{0, 5}, {1, 20}] do
        wait = Backoff.schedule(legacy, used, now)
        assert wait["delay_seconds"] == delay
        assert Backoff.pending?(waiting(legacy, wait))
      end
    end

    legacy = attempt("provider_overloaded", "automatic-provider-backoff-v1")
    refute Backoff.transient?(legacy)
    refute Backoff.pending?(waiting(legacy, Backoff.schedule(legacy, 0, now)))
  end

  test "429, exhausted usage and unknown policies cannot acquire automatic wait authority" do
    for reason <- ~w(rate_limited usage_limit provider_error),
        policy <- ["automatic-provider-backoff-v1", Backoff.policy(), "future"] do
      claim = attempt(reason, policy)
      refute Backoff.transient?(claim)
      refute Backoff.pending?(waiting(claim, Backoff.schedule(claim, 0, DateTime.utc_now())))
    end
  end
end
