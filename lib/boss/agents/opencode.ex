defmodule Boss.Agents.OpenCode do
  @moduledoc """
  Bounded OpenCode (`opencode run --pure --format json`) protocol for read-only
  planning/review/diagnosis (`OPENCODE_PERMISSION` write-deny) and isolated-worktree
  implementation (`--auto`). Session IDs and raw tool output are never retained.
  """
  alias Boss.Agents.Cursor

  @line_limit 1_048_576
  @output_limit 8_388_608
  @text_limit 131_072

  @read_only_permission Jason.encode!(%{
                          "*" => "deny",
                          "read" => "allow",
                          "glob" => "allow",
                          "grep" => "allow",
                          "list" => "allow",
                          "external_directory" => "allow"
                        })

  def args(kind, selection \\ %{})

  def args(:implement, selection) do
    ["run", "--pure", "--auto", "--format", "json"] ++ selection_flags(selection)
  end

  def args(kind, selection) when kind in [:plan, :resolve, :intake, :review, :merge_review] do
    ["run", "--pure", "--format", "json"] ++ selection_flags(selection)
  end

  def env(:implement), do: [{"OPENCODE_DISABLE_AUTOUPDATE", "1"}]

  def env(kind) when kind in [:plan, :resolve, :intake, :review, :merge_review] do
    [
      {"OPENCODE_PERMISSION", @read_only_permission},
      {"OPENCODE_DISABLE_AUTOUPDATE", "1"}
    ]
  end

  defp selection_flags(selection) when is_map(selection) do
    model =
      case selection[:model_id] || selection["model_id"] do
        m when is_binary(m) and m != "" -> ["--model", m]
        _ -> []
      end

    effort =
      case selection[:reasoning_effort] || selection["reasoning_effort"] do
        e when is_binary(e) and e != "" -> ["--variant", e]
        _ -> []
      end

    model ++ effort
  end

  defp selection_flags(_), do: []

  def new do
    %{
      buffer: "",
      stdout_bytes: 0,
      stderr_bytes: 0,
      stderr_head: "",
      texts: [],
      text_bytes: 0,
      started: false,
      last_finish_reason: nil,
      error: nil,
      error_message: nil,
      input_tokens: 0,
      output_tokens: 0,
      cached_input_tokens: 0
    }
  end

  def feed(state, {:stdout, bytes}) when is_binary(bytes) do
    state = %{state | stdout_bytes: state.stdout_bytes + byte_size(bytes)}

    cond do
      state.stdout_bytes + state.stderr_bytes > @output_limit ->
        %{state | error: :output_limit, buffer: ""}

      state.error != nil ->
        state

      true ->
        consume_lines(state, state.buffer <> bytes)
    end
  end

  def feed(state, {:stderr, bytes}) when is_binary(bytes) do
    state = %{state | stderr_bytes: state.stderr_bytes + byte_size(bytes)}

    head =
      if byte_size(state.stderr_head) < 4_096 do
        room = 4_096 - byte_size(state.stderr_head)
        state.stderr_head <> binary_part(bytes, 0, min(byte_size(bytes), room))
      else
        state.stderr_head
      end

    state = %{state | stderr_head: head}

    if state.stdout_bytes + state.stderr_bytes > @output_limit do
      %{state | error: :output_limit, buffer: ""}
    else
      state
    end
  end

  def feed(state, _), do: state

  def finish(state) do
    state =
      if state.error == nil and state.buffer != "" do
        consume_event(%{state | buffer: ""}, String.trim(state.buffer))
      else
        state
      end

    if state.error == nil and state.started and state.last_finish_reason in ["stop", "end_turn"] do
      joined = state.texts |> Enum.reverse() |> Enum.join("\n")
      {:ok, Cursor.extract_json_or_raw(joined), summary(state)}
    else
      {:error, notice(state.stderr_head, state.error_message)}
    end
  end

  def report(stdout) when is_binary(stdout) do
    new()
    |> feed({:stdout, stdout})
    |> finish()
    |> case do
      {:ok, text, sum} -> {:ok, text, sum}
      {:error, _} -> :error
    end
  end

  def report(_), do: :error

  def notice(stderr, error_msg \\ nil) do
    line = safe_line(error_msg) || safe_line(stderr)

    class =
      cond do
        line &&
            String.contains?(String.downcase(line), [
              "authentication",
              "not logged in",
              "invalid api key",
              "unauthorized",
              "missing api key",
              "credential"
            ]) ->
          "auth"

        line &&
            String.contains?(String.downcase(line), [
              "model not found",
              "model unavailable",
              "providermodelnotfounderror"
            ]) ->
          "model_unavailable"

        line &&
            String.contains?(String.downcase(line), [
              "rate limit",
              "quota",
              "credit balance",
              "insufficient credits",
              "out of credits",
              "billing",
              "usage limit",
              "overloaded",
              "too many requests"
            ]) ->
          "rate_limit"

        true ->
          nil
      end

    reason =
      if line do
        "OpenCode: #{line}"
      else
        "OpenCode did not finish with a valid result and clean exit. No fallback was started."
      end

    %{reason: reason, class: class}
  end

  def summary(state) do
    usage =
      %{
        "input_tokens" => state.input_tokens,
        "output_tokens" => state.output_tokens,
        "cached_input_tokens" => state.cached_input_tokens
      }
      |> Map.filter(fn {_, v} -> is_integer(v) and v > 0 end)

    %{
      "type" => "step_finish",
      "reason" => state.last_finish_reason,
      "stdout_bytes" => state.stdout_bytes,
      "stderr_bytes" => state.stderr_bytes,
      "usage" => usage
    }
  end

  defp consume_lines(state, data) do
    case :binary.match(data, "\n") do
      :nomatch ->
        if byte_size(data) > @line_limit do
          %{state | error: :line_limit, buffer: ""}
        else
          %{state | buffer: data}
        end

      {idx, 1} when idx > @line_limit ->
        %{state | error: :line_limit, buffer: ""}

      {idx, 1} ->
        <<line::binary-size(^idx), _nl, rest::binary>> = data
        state = consume_event(%{state | buffer: ""}, String.trim(line))
        if state.error, do: state, else: consume_lines(state, rest)
    end
  end

  defp consume_event(state, ""), do: state

  defp consume_event(state, line) do
    case Jason.decode(line) do
      {:ok, %{"type" => "step_start"}} ->
        %{state | started: true}

      {:ok, %{"type" => "text", "part" => %{"text" => chunk}}} when is_binary(chunk) ->
        append_text(%{state | started: true}, chunk)

      {:ok, %{"type" => "step_finish", "part" => part}} when is_map(part) ->
        reason = part["reason"]
        tokens = if is_map(part["tokens"]), do: part["tokens"], else: %{}
        cache = if is_map(tokens["cache"]), do: tokens["cache"], else: %{}

        state = %{
          state
          | started: true,
            last_finish_reason: reason,
            input_tokens: state.input_tokens + int_or_zero(tokens["input"]),
            output_tokens: state.output_tokens + int_or_zero(tokens["output"]),
            cached_input_tokens: state.cached_input_tokens + int_or_zero(cache["read"])
        }

        if reason == "error" do
          %{state | error: :step_error}
        else
          state
        end

      {:ok, %{"type" => "error"} = ev} ->
        msg = extract_error_message(ev["error"] || ev)
        %{state | error: :agent_error, error_message: msg}

      {:ok, %{"type" => _}} ->
        state

      _ ->
        state
    end
  end

  defp append_text(state, chunk) do
    next_bytes = state.text_bytes + byte_size(chunk)

    if next_bytes <= @text_limit do
      %{state | texts: [chunk | state.texts], text_bytes: next_bytes}
    else
      keep =
        binary_part(
          chunk,
          max(byte_size(chunk) - @text_limit, 0),
          min(byte_size(chunk), @text_limit)
        )

      %{state | texts: [keep], text_bytes: byte_size(keep)}
    end
  end

  defp extract_error_message(%{"data" => %{"message" => m}}) when is_binary(m), do: m
  defp extract_error_message(%{"message" => m}) when is_binary(m), do: m
  defp extract_error_message(%{"name" => n}) when is_binary(n), do: n
  defp extract_error_message(m) when is_binary(m), do: m
  defp extract_error_message(_), do: nil

  defp int_or_zero(n) when is_integer(n) and n >= 0 and n <= 1_000_000_000_000, do: n
  defp int_or_zero(_), do: 0

  defp safe_line(text) when is_binary(text) do
    if String.valid?(text) do
      text
      |> String.replace(~r/\e\[[0-9;]*[A-Za-z]/, "")
      |> String.split(~r/\R/u, parts: 4)
      |> Enum.map(&redact/1)
      |> Enum.find(&(String.trim(&1) != ""))
      |> case do
        nil -> nil
        line -> line |> String.replace(~r/[\p{Cc}]+/u, " ") |> String.trim() |> clip(240)
      end
    end
  end

  defp safe_line(_), do: nil

  defp redact(line) do
    Regex.replace(
      ~r/(?i)(api[_-]?key|token|secret|bearer|authorization)(\s*[:=]\s*)\S+/,
      line,
      "\\1\\2[redacted]"
    )
  end

  defp clip(line, max) do
    if byte_size(line) <= max, do: line, else: binary_part(line, 0, max) <> "…"
  end
end
