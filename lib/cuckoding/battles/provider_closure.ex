defmodule Cuckoding.Battles.ProviderClosure do
  @moduledoc "Read retained native closure facts only; no role result or continuation authority."
  alias Cuckoding.Battles.Snapshot
  alias Cuckoding.NativeHelper

  @policy "retained-provider-closure-v1"
  @fields ~w(status request_id attempt_sha256 agent_id kind cleanup_verified pid spawned_at_ms elapsed_ms receipt_sha256)

  def policy, do: @policy
  def enabled?(snapshot), do: snapshot["provider_closure"] == @policy

  def binding_for(attempt) do
    role = attempt.request["role"]

    %{
      "version" => @policy,
      "attempt_sha256" => Snapshot.digest(attempt.request),
      "agent_id" => role["agent_id"],
      "kind" => role["kind"],
      "identity" => role["identity"],
      "model" => role["model"],
      "effort" => role["effort"]
    }
  end

  def inspect(attempt, active?) do
    result =
      NativeHelper.request(
        nil,
        ["--inspect-provider-closure"],
        5_000,
        &decode_observation/1,
        8192,
        active?: active?,
        input: Jason.encode!(%{"request_id" => attempt.id, "closure" => binding_for(attempt)})
      )

    case result do
      %{"status" => "observed", "cleanup_verified" => true, "receipt" => receipt} -> receipt
      _ -> %{"status" => "closure_unavailable", "cleanup_verified" => false}
    end
  end

  # NativeHelper times this read separately from the retained provider execution.
  defp decode_observation(bytes) do
    receipt = normalize(bytes)

    %{
      "status" => "observed",
      "cleanup_verified" => receipt["cleanup_verified"],
      "receipt" => receipt
    }
  end

  def normalize(bytes) when is_binary(bytes) and byte_size(bytes) <= 8192 do
    with {:ok, %{"status" => "provider_closed", "cleanup_verified" => true} = value} <-
           Jason.decode(bytes),
         true <- Enum.sort(Map.keys(value)) == Enum.sort(@fields),
         {:ok, _} <- Ecto.UUID.cast(value["request_id"]),
         true <-
           value["agent_id"] == "codex" or match?({:ok, _}, Ecto.UUID.cast(value["agent_id"])),
         true <- value["kind"] in ~w(codex cursor),
         true <- hash?(value["attempt_sha256"]) and hash?(value["receipt_sha256"]),
         true <- is_integer(value["pid"]) and value["pid"] in 1..2_147_483_647,
         true <-
           is_integer(value["spawned_at_ms"]) and value["spawned_at_ms"] in 1..9_999_999_999_999,
         true <- is_integer(value["elapsed_ms"]) and value["elapsed_ms"] in 0..900_000 do
      value
    else
      _ -> %{"status" => "closure_unavailable", "cleanup_verified" => false}
    end
  end

  def normalize(_), do: %{"status" => "closure_unavailable", "cleanup_verified" => false}

  def verified?(attempt, receipt) do
    is_map(receipt) and normalize(Jason.encode!(receipt)) == receipt and
      receipt["status"] == "provider_closed" and receipt["cleanup_verified"] == true and
      Map.take(receipt, ~w(request_id attempt_sha256 agent_id kind)) ==
        Map.merge(Map.take(binding_for(attempt), ~w(attempt_sha256 agent_id kind)), %{
          "request_id" => attempt.id
        })
  end

  defp hash?(text), do: is_binary(text) and Regex.match?(~r/\A[0-9a-f]{64}\z/, text)
end
