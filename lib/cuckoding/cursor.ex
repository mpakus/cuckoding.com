defmodule Cuckoding.Cursor do
  @moduledoc "Private Cursor setup and bounded host-mediated task operations."
  @behaviour Cuckoding.AgentAdapter
  alias Cuckoding.Codex
  @version "2026.09.15-d2fe57e"
  @plan_fields ~w(status grant transport requested_model observed_model effort runtime_model runtime_parameters thread_id turn_id request_id proposal pid spawned_at_ms elapsed_ms cleanup_verified)
  def task_version, do: @version

  @impl true
  def probe(identity, directory, active?) do
    Codex.observe(identity, directory, active?, "--probe-cursor", &normalize/1, 1024, 8_000)
  end

  @impl true
  def inspect_connection(identity, directory, active?) do
    Codex.observe(
      identity,
      directory,
      active?,
      "--inspect-cursor",
      &normalize_connection/1,
      524_288,
      18_000,
      progress: :no_progress
    )
  end

  @impl true
  def authorize(identity, directory, operation, active?, progress)
      when operation in [:login, :logout] do
    Codex.observe(
      identity,
      directory,
      active?,
      "--#{operation}-cursor",
      &normalize_connection/1,
      524_288,
      if(operation == :login, do: 615_000, else: 18_000),
      progress: progress,
      login_kind: "cursor"
    )
  end

  @impl true
  def check_model(_, _, _, _, _, _), do: %{"status" => "unsupported_grant"}
  @impl true
  def plan(identity, profile, scratch, request, active?) do
    if active?.() do
      Codex.observe(
        identity,
        profile,
        active?,
        "--plan-cursor-brief",
        &Cuckoding.Planning.normalize/1,
        65_536,
        125_000,
        progress: :no_progress,
        args: [scratch, request["model"]],
        input:
          Jason.encode!(Map.take(request, ~w(request_id brief instructions documents contract))) <>
            "\n"
      )
    else
      %{"status" => "cancelled"}
    end
  end

  @doc false
  def runtime_metadata?(%{
        "transport" => "cursor-acp-v1",
        "effort" => nil,
        "runtime_model" => model,
        "runtime_parameters" => parameters
      })
      when is_map(parameters) do
    identifier?(model) and map_size(parameters) <= 12 and
      Enum.all?(parameters, fn {key, value} -> identifier?(key) and identifier?(value) end)
  end

  def runtime_metadata?(_), do: false

  @doc false
  def normalize_plan_fields(result) do
    if result["status"] == "planned" and result["grant"] == "cursor-plan-no-tools-v1" and
         result["cleanup_verified"] == true and Map.keys(result) -- @plan_fields == [] and
         runtime_metadata?(result) and
         Enum.all?(~w(requested_model observed_model thread_id turn_id), &identifier?(result[&1])) do
      result
      |> Map.take(
        ~w(status grant transport requested_model observed_model effort runtime_model runtime_parameters thread_id turn_id)
      )
      |> Map.merge(Codex.public_fields(result))
    else
      %{"status" => "invalid_response"}
    end
  end

  defp identifier?(id),
    do: is_binary(id) and byte_size(id) in 1..128 and Regex.match?(~r/\A[a-zA-Z0-9._\/-]+\z/, id)

  @impl true
  def run_task(identity, profile, scratch, request, active?) do
    if active?.() do
      Codex.observe(
        identity,
        profile,
        active?,
        "--run-cursor-task",
        &Cuckoding.TaskTurn.normalize/1,
        65_536,
        305_000,
        progress: :no_progress,
        args: [scratch, request["model"]],
        input:
          Jason.encode!(
            Map.take(
              request,
              ~w(request_id contract access workspace prompt instructions closure)
            )
          ) <> "\n"
      )
    else
      %{"status" => "cancelled"}
    end
  end

  def normalize(bytes) when is_binary(bytes) and byte_size(bytes) <= 1024 do
    case Codex.decode_receipt(bytes) do
      {:ok, %{"status" => "observed", "version" => version} = result} when is_binary(version) ->
        if Regex.match?(~r/\A[0-9]{4}\.[0-9]{2}\.[0-9]{2}-[a-f0-9]{7}\z/, version) do
          Map.merge(Codex.public_fields(result), %{
            "status" => if(version == @version, do: "supported", else: "unsupported"),
            "version" => version
          })
        else
          %{"status" => "invalid_output"}
        end

      _ ->
        Codex.normalize(bytes)
    end
  end

  def normalize(_), do: %{"status" => "invalid_output"}

  def normalize_connection(bytes) when is_binary(bytes) and byte_size(bytes) <= 524_288 do
    case Codex.decode_receipt(bytes) do
      {:ok,
       %{"status" => "checked", "authorization" => "cursor", "catalog_status" => status} = result}
      when status in ~w(fresh failed) ->
        public =
          Map.merge(
            Map.take(result, ~w(status authorization catalog_status)),
            Codex.public_fields(result)
          )

        rows = result["models"]

        if status == "fresh" and valid_models?(rows) do
          Map.put(
            public,
            "models",
            Enum.map(rows, &Map.take(&1, ~w(id model name default hidden)))
          )
        else
          Map.merge(public, %{"catalog_status" => "failed", "catalog_error" => "refresh_failed"})
        end

      {:ok, %{"authorization" => "chatgpt"}} ->
        %{"status" => "invalid_output"}

      _ ->
        Codex.normalize_connection(bytes)
    end
  end

  def normalize_connection(_), do: %{"status" => "invalid_output"}

  defp valid_models?(rows),
    do:
      is_list(rows) and length(rows) <= 512 and Enum.all?(rows, &valid_model?/1) and
        Enum.uniq_by(rows, & &1["id"]) == rows

  defp valid_model?(%{
         "id" => id,
         "model" => model,
         "name" => name,
         "default" => default,
         "hidden" => hidden
       }) do
    Enum.all?(
      [id, model],
      &(is_binary(&1) and byte_size(&1) in 1..128 and Regex.match?(~r/\A[a-zA-Z0-9._\/-]+\z/, &1))
    ) and
      is_binary(name) and String.valid?(name) and byte_size(name) in 1..128 and
      not Regex.match?(~r/[\x00-\x1f\x7f]/, name) and is_boolean(default) and is_boolean(hidden)
  end

  defp valid_model?(_), do: false
end
