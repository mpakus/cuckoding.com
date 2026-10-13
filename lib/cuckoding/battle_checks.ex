defmodule Cuckoding.BattleChecks do
  @moduledoc "Literal, frozen project checks in a disposable native verification checkout."
  alias Cuckoding.{Codex, NativeHelper, Storage, Tools}
  @directories ~w(/usr/bin /bin)
  @errors ~w(failed cancelled timeout output_limit source_limit source_changed unsafe_workspace executable_changed unsupported_version unsupported_grant invalid_request attempt_exists launch_failed cleanup_uncertain invalid_output unavailable journal_failed)

  # Metadata lookup only: no project scripts, shell startup, or executable probe.
  def resolve(checks) when is_list(checks) and length(checks) in 1..8 do
    with %{"status" => "found", "path" => path} <- Tools.discover()["rtk"],
         {:ok, rtk} <- Codex.executable(path),
         true <- Enum.all?(checks, &(&1["timeout_seconds"] in 1..300)),
         true <- Enum.sum(Enum.map(checks, & &1["timeout_seconds"])) <= 600 do
      resolve_identities(checks, rtk)
    else
      _ -> {:error, "check_runtime_unavailable"}
    end
  end

  def resolve(_), do: {:error, "checks_required"}

  defp resolve_identities(checks, rtk) do
    Enum.reduce_while(checks, {:ok, []}, fn check, {:ok, resolved} ->
      identity = Enum.find_value(@directories, &identity(Path.join(&1, check["executable"])))

      if identity,
        do:
          {:cont,
           {:ok, resolved ++ [Map.merge(check, %{"identity" => identity, "rtk_identity" => rtk})]}},
        else: {:halt, {:error, "check_executable_unavailable"}}
    end)
  end

  defp identity(path) do
    case Codex.executable(path) do
      {:ok, identity} ->
        if Path.dirname(identity["path"]) in @directories and native_binary?(identity["path"]),
          do: identity

      _ ->
        nil
    end
  end

  def run(attempt, workspace, checks, codex, active?) do
    request = %{
      "request_id" => attempt.id,
      "scratch" => Storage.probe_directory!(attempt.id, 1),
      "workspace" => workspace,
      "checks" => checks,
      "codex" => codex
    }

    result =
      NativeHelper.request(attempt, ["--battle-checks"], 620_000, &normalize/1, 16_384,
        active?: active?,
        input: Jason.encode!(request)
      )

    if result["request_id"] in [nil, attempt.id],
      do: result,
      else: %{"status" => "invalid_output"}
  end

  # The initial grant cannot spawn interpreters or child toolchains. Keep executable
  # lookup in system directories and refuse scripts before any paid provider turn.
  # The sole caller verifies a canonical regular executable directly in /usr/bin or /bin.
  # Read four magic bytes only; native admission revalidates its complete identity.
  # sobelow_skip ["Traversal.FileModule"]
  defp native_binary?(path) do
    case File.open(path, [:read, :binary]) do
      {:ok, file} ->
        magic = IO.binread(file, 4)
        File.close(file)

        magic in [
          <<0xCF, 0xFA, 0xED, 0xFE>>,
          <<0xFE, 0xED, 0xFA, 0xCF>>,
          <<0xCA, 0xFE, 0xBA, 0xBE>>,
          <<0xBE, 0xBA, 0xFE, 0xCA>>
        ]

      _ ->
        false
    end
  end

  def normalize(bytes) when is_binary(bytes) and byte_size(bytes) <= 16_384 do
    case Jason.decode(bytes) do
      {:ok, %{"status" => status} = result} when status in ["passed" | @errors] ->
        if envelope?(result) and checks?(result["checks"]) and outcome?(result),
          do:
            Map.take(result, ~w(status request_id contract candidate_sha checks cleanup_verified)),
          else: %{"status" => "invalid_output"}

      _ ->
        %{"status" => "invalid_output"}
    end
  end

  def normalize(_), do: %{"status" => "invalid_output"}

  defp outcome?(%{"status" => status} = result) when status in ~w(passed failed) do
    result["cleanup_verified"] == true and result["checks"] != [] and
      Enum.all?(result["checks"], &(&1["cleanup_verified"] == true)) and
      (status != "passed" or Enum.all?(result["checks"], &(&1["status"] == "passed")))
  end

  defp outcome?(result), do: is_boolean(result["cleanup_verified"])

  defp checks?(checks) when is_list(checks) and length(checks) <= 8,
    do:
      Enum.all?(checks, &check?/1) and length(Enum.uniq_by(checks, & &1["id"])) == length(checks)

  defp checks?(_), do: false

  defp envelope?(result),
    do:
      result["contract"] == "codex-check-single-process-v1" and
        match?({:ok, _}, Ecto.UUID.cast(result["request_id"])) and
        Cuckoding.GitPreview.hash?(result["candidate_sha"], 40)

  defp check?(check) when is_map(check) do
    Map.keys(check) --
      ~w(id status exit_code stdout_sha256 stdout_bytes pid spawned_at_ms elapsed_ms cleanup_verified child_pid child_start_seconds child_start_microseconds) ==
      [] and
      match?({:ok, _}, Ecto.UUID.cast(check["id"])) and check["status"] in ["passed" | @errors] and
      is_boolean(check["cleanup_verified"]) and child_identity?(check) and
      check_result?(check) and process_identity?(check)
  end

  defp check?(_), do: false

  defp check_result?(check) do
    integer_in?(check["exit_code"], -1..255) and
      (check["status"] != "passed" or check["exit_code"] == 0) and
      Cuckoding.GitPreview.hash?(check["stdout_sha256"], 64) and
      integer_in?(check["stdout_bytes"], 0..65_536) and
      integer_in?(check["elapsed_ms"], 0..310_000)
  end

  defp process_identity?(check) do
    is_integer(check["pid"]) and check["pid"] > 0 and
      is_integer(check["spawned_at_ms"]) and check["spawned_at_ms"] > 0
  end

  defp integer_in?(value, range), do: is_integer(value) and value in range

  defp child_identity?(check) do
    fields = Map.take(check, ~w(child_pid child_start_seconds child_start_microseconds))

    fields == %{} or
      (map_size(fields) == 3 and is_integer(fields["child_pid"]) and fields["child_pid"] > 0 and
         is_integer(fields["child_start_seconds"]) and fields["child_start_seconds"] > 0 and
         is_integer(fields["child_start_microseconds"]) and
         fields["child_start_microseconds"] in 0..999_999)
  end
end
