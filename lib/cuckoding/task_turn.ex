defmodule Cuckoding.TaskTurn do
  @moduledoc "Public task receipts only; a role report does not establish task completion."
  alias Cuckoding.Codex

  @tool_errors ~w(invalid_tool unsafe_workspace unsafe_file unsupported_file file_changed file_missing tool_limit journal_failed write_failed attempt_exists)
  @errors ~w(launch_failed timeout cancelled invalid_output executable_changed helper_unavailable connection_lost provider_error unexpected_message profile_mismatch unsupported_profile unsafe_profile profile_busy cleanup_uncertain not_connected model_unavailable model_mismatch unsupported_grant invalid_response unexpected_tool turn_failed interrupted)

  def normalize(bytes) when is_binary(bytes) and byte_size(bytes) <= 65_536 do
    with {:ok, %{"status" => status} = result} <- Codex.decode_receipt(bytes),
         true <- status in ["task_finished" | @errors ++ @tool_errors],
         true <-
           not Map.has_key?(result, "cleanup_verified") or is_boolean(result["cleanup_verified"]),
         true <- tools?(Map.get(result, "tools", [])),
         true <- changes?(result) do
      if status == "task_finished" do
        normalize_success(result)
      else
        result
        |> Map.take(~w(status tools changes cleanup_verified))
        |> Map.merge(Codex.public_fields(result))
      end
    else
      _ -> %{"status" => "invalid_output"}
    end
  end

  def normalize(_), do: %{"status" => "invalid_output"}

  defp normalize_success(result) do
    valid =
      result["grant"] == "host-task-tools-v1" and result["access"] in ~w(read write) and
        match?({:ok, _}, Ecto.UUID.cast(result["request_id"])) and
        Enum.all?(~w(requested_model observed_model thread_id turn_id), &id?(result[&1])) and
        runtime?(result) and
        report?(result["report"]) and
        Enum.all?(Map.get(result, "tools", []), &(&1["status"] == "completed"))

    if valid,
      do:
        result
        |> Map.take(
          ~w(status request_id grant transport access requested_model observed_model effort runtime_model runtime_parameters thread_id turn_id report tools changes cleanup_verified)
        )
        |> Map.merge(Codex.public_fields(result)),
      else: %{"status" => "invalid_output"}
  end

  defp runtime?(%{"transport" => "cursor-acp-v1", "effort" => nil} = result) do
    parameters = result["runtime_parameters"]

    id?(result["runtime_model"]) and is_map(parameters) and map_size(parameters) <= 12 and
      Enum.all?(parameters, fn {key, value} -> id?(key) and id?(value) end)
  end

  defp runtime?(result), do: is_nil(result["transport"]) and id?(result["effort"])

  defp tools?(tools) when is_list(tools) and length(tools) <= 64 do
    Enum.all?(tools, &tool?/1) and
      length(Enum.uniq_by(tools, & &1["call_id"])) == length(tools)
  end

  defp tools?(_), do: false

  defp tool?(%{"call_id" => id, "tool" => tool, "status" => status} = entry) do
    Map.keys(entry) -- ~w(call_id tool status sha256 path) == [] and id?(id) and
      tool in ~w(list_files read_file edit_file) and status in ["completed" | @tool_errors] and
      (not Map.has_key?(entry, "path") or path?(entry["path"], tool == "list_files")) and
      (is_nil(entry["sha256"]) or
         (is_binary(entry["sha256"]) and Regex.match?(~r/\A[0-9a-f]{64}\z/, entry["sha256"])))
  end

  defp tool?(_), do: false

  defp changes?(%{"changes" => changes} = result)
       when is_list(changes) and length(changes) <= 64 do
    edits =
      for %{"tool" => "edit_file", "status" => "completed", "path" => path, "sha256" => sha} <-
            Map.get(result, "tools", []),
          into: %{},
          do: {path, sha}

    (result["access"] != "read" or changes == []) and
      Enum.all?(changes, &change?(&1, edits)) and
      length(Enum.uniq_by(changes, & &1["path"])) == length(changes) and
      map_size(edits) == length(changes)
  end

  defp changes?(result), do: not Map.has_key?(result, "changes")

  defp change?(change, edits) when is_map(change) and map_size(change) == 2,
    do:
      path?(change["path"], false) and is_binary(change["sha256"]) and
        Regex.match?(~r/\A[0-9a-f]{64}\z/, change["sha256"]) and
        edits[change["path"]] == change["sha256"]

  defp change?(_, _), do: false

  defp path?("", true), do: true

  defp path?(path, _) when is_binary(path) and byte_size(path) in 1..240 do
    parts = String.split(path, "/")

    length(parts) <= 8 and
      Enum.all?(parts, fn part ->
        lower = String.downcase(part)

        Regex.match?(~r/\A[A-Za-z0-9_-][A-Za-z0-9_.-]*\z/, part) and
          lower not in ~w(agents.md claude.md node_modules deps _build target vendor build dist) and
          not String.starts_with?(lower, ~w(secret credential token id_rsa id_ed25519)) and
          Path.extname(lower) not in ~w(.pem .key .p12 .pfx)
      end)
  end

  defp path?(_, _), do: false

  defp report?(%{"summary" => text, "outcome" => outcome} = report) do
    map_size(report) == 2 and outcome in ~w(completed changes_requested blocked) and
      is_binary(text) and byte_size(text) in 1..4000 and String.valid?(text) and
      String.trim(text) != "" and not Regex.match?(~r/[\x00-\x08\x0B-\x1F\x7F]/, text)
  end

  defp report?(_), do: false

  defp id?(id),
    do:
      is_binary(id) and byte_size(id) in 1..128 and
        Regex.match?(~r/\A[a-zA-Z0-9._\/-]+\z/, id)
end
