defmodule Cuckoding.ProviderClosureTest do
  use ExUnit.Case, async: true
  alias Cuckoding.Battles.ProviderClosure

  test "closure observations require bounded public fields and an exact frozen attempt" do
    attempt = %{
      id: Ecto.UUID.generate(),
      request: %{"role" => %{"agent_id" => "codex", "kind" => "codex"}}
    }

    native =
      ProviderClosure.binding_for(attempt)
      |> Map.take(~w(attempt_sha256 agent_id kind))
      |> Map.merge(%{
        "status" => "provider_closed",
        "request_id" => attempt.id,
        "cleanup_verified" => true,
        "pid" => 1,
        "spawned_at_ms" => 1,
        "elapsed_ms" => 0,
        "receipt_sha256" => String.duplicate("a", 64)
      })

    assert ProviderClosure.verified?(attempt, native)
    refute ProviderClosure.verified?(%{attempt | id: Ecto.UUID.generate()}, native)

    refute ProviderClosure.verified?(
             %{attempt | request: Map.put(attempt.request, "stage", "changed")},
             native
           )

    for malformed <- [
          Map.put(native, "cleanup_verified", false),
          Map.put(native, "cleanup_verified", "true"),
          Map.put(native, "status", "completed"),
          Map.put(native, "raw_provider", "private-canary"),
          Map.put(native, "pid", 0),
          Map.put(native, "elapsed_ms", 900_001),
          Map.put(native, "receipt_sha256", "bad"),
          Map.delete(native, "attempt_sha256")
        ] do
      assert ProviderClosure.normalize(Jason.encode!(malformed)) == %{
               "status" => "closure_unavailable",
               "cleanup_verified" => false
             }

      refute ProviderClosure.verified?(attempt, malformed)
    end

    refute ProviderClosure.enabled?(%{})
    refute ProviderClosure.enabled?(%{"provider_closure" => "future-policy"})
  end
end
