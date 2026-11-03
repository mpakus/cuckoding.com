defmodule Boss.Agents.Codex do
  @moduledoc "Bounded Codex JSONL metadata. Raw model/tool output is never retained."
  @line_limit 262_144
  @types ~w(thread.started turn.started turn.completed turn.failed error item.started item.updated item.completed)

  def args, do: command_args("workspace-write", [])

  def args(:implement, nil), do: args()

  def args(:review, output_path),
    do:
      command_args("read-only", [
        "--output-schema",
        Application.app_dir(:boss, "priv/review_schema.json"),
        "--output-last-message",
        output_path
      ])

  def args(:plan, output_path),
    do:
      command_args("read-only", [
        "--output-schema",
        Application.app_dir(:boss, "priv/plan_schema.json"),
        "--output-last-message",
        output_path
      ])

  def args(:intake, output_path),
    do:
      command_args("read-only", [
        "--output-schema",
        Application.app_dir(:boss, "priv/intake_schema.json"),
        "--output-last-message",
        output_path
      ])

  def args(:resolve, output_path),
    do:
      command_args("read-only", [
        "--output-schema",
        Application.app_dir(:boss, "priv/resolution_schema.json"),
        "--output-last-message",
        output_path
      ])

  def args(kind, output_path, nil), do: args(kind, output_path)

  def args(kind, output_path, %{"model" => model, "reasoning_effort" => effort} = profile)
      when model in [
             "gpt-6-astra",
             "gpt-6.1-sol",
             "gpt-6-luna",
             "gpt-5.6-sol",
             "gpt-5.6-terra",
             "gpt-5.6-luna"
           ] and
             effort in ["medium", "high", "xhigh"] do
    unless Boss.Agents.ModelCatalog.profile?(profile),
      do: raise(ArgumentError, "invalid model profile")

    argv = args(kind, output_path)

    Enum.drop(argv, -1) ++
      ["--model", model, "--config", "model_reasoning_effort=\"#{effort}\"", "-"]
  end

  defp command_args(sandbox, extra),
    do:
      [
        "--ask-for-approval",
        "never",
        "exec",
        "--ignore-user-config",
        "--ephemeral",
        "--sandbox",
        sandbox,
        "--json",
        "--color",
        "never"
      ] ++ extra ++ ["-"]

  def prompt(source) do
    text =
      """
      Implement the following saved task specification in this isolated worktree.
      Inspect the project instructions first. Make only changes required by this task.
      Run appropriate focused checks. Do not commit, merge, push, or start background services.
      Work only in this worktree. Explain any blocker rather than claiming completion.
      Your final message is not approval or verified delivery; BOSS records a manual attempt.

      Saved specification:
      """ <> source

    if byte_size(text) <= 1_048_576, do: {:ok, text}, else: {:error, :input_too_large}
  end

  def new,
    do: %{
      buffer: "",
      count: 0,
      events: [],
      stdout_bytes: 0,
      stderr_bytes: 0,
      started: false,
      terminal: false,
      error: nil,
      error_class: nil,
      usage: %{}
    }

  def feed(state, {:stderr, bytes}),
    do: %{state | stderr_bytes: state.stderr_bytes + byte_size(bytes)}

  def feed(state, {:stdout, bytes}) do
    state = %{state | stdout_bytes: state.stdout_bytes + byte_size(bytes)}
    if state.error, do: state, else: lines(state, state.buffer <> bytes)
  end

  def feed(state, _), do: state

  def complete?(state),
    do: state.started and state.terminal and is_nil(state.error) and state.buffer == ""

  def summary(state),
    do: %{
      "events" => Enum.reverse(state.events),
      "event_count" => state.count,
      "stdout_bytes" => state.stdout_bytes,
      "stderr_bytes" => state.stderr_bytes,
      "error_class" => state.error_class,
      "usage" => state.usage
    }

  defp lines(state, data) do
    case :binary.match(data, "\n") do
      :nomatch ->
        if byte_size(data) > @line_limit,
          do: fail(state, :line_limit),
          else: %{state | buffer: data}

      {index, 1} when index > @line_limit ->
        fail(state, :line_limit)

      {index, 1} ->
        <<line::binary-size(^index), _newline, rest::binary>> = data
        state = event(%{state | buffer: ""}, line)
        if state.error, do: state, else: lines(state, rest)
    end
  end

  defp event(state, ""), do: state
  defp event(%{count: count} = state, _) when count >= 4096, do: fail(state, :event_limit)

  defp event(state, line) do
    case JSON.decode(line) do
      {:ok, %{"type" => type} = event} when is_binary(type) and byte_size(type) in 1..100 ->
        cond do
          state.terminal ->
            fail(state, :event_after_terminal)

          type == "turn.started" and state.started ->
            fail(state, :duplicate_turn)

          type == "turn.completed" and not state.started ->
            fail(state, :missing_turn)

          type in ["error", "turn.failed"] ->
            state = %{state | error_class: classify_error(event)}
            fail(record(state, type), :agent_error)

          true ->
            state = record(state, if(type in @types, do: type, else: "other"))
            state = if type == "turn.started", do: %{state | started: true}, else: state

            if type == "turn.completed",
              do: %{state | terminal: true, usage: usage(event["usage"])},
              else: state
        end

      _ ->
        fail(state, :invalid_jsonl)
    end
  end

  defp record(state, type),
    do: %{
      state
      | count: state.count + 1,
        events: Enum.take([%{"type" => type, "sequence" => state.count + 1} | state.events], 20)
    }

  defp fail(state, reason),
    do: %{state | error: reason, error_class: state.error_class || "transport", buffer: ""}

  defp classify_error(event) do
    error = if is_map(event["error"]), do: event["error"], else: %{}
    code = event["code"] || error["code"] || error["type"]
    status = event["status_code"] || error["status_code"]
    message = event["message"] || error["message"] || event["error"]
    # Inspect only a bounded transient message; retain the fixed category, never its text.
    message =
      if is_binary(message), do: String.slice(message, 0, 4096) |> String.downcase(), else: ""

    cond do
      code in ~w(model_not_found unsupported_model model_not_available invalid_model) or
          Regex.match?(
            ~r/(?:model.{0,120}(?:does not exist|not found|not supported|not available|not accessible)|(?:unsupported|unknown) model)/s,
            message
          ) ->
        "model_unavailable"

      code in ~w(invalid_api_key authentication_error unauthorized permission_denied) or
        status in [401, 403] or
          Regex.match?(
            ~r/invalid api key|authentication failed|not authenticated|please (?:log|sign) in/,
            message
          ) ->
        "auth"

      code in ~w(rate_limit_exceeded insufficient_quota usage_limit_reached) or status == 429 or
          Regex.match?(
            ~r/rate limit|quota exceeded|exceeded your current quota|usage limit/,
            message
          ) ->
        "rate_limit"

      code in ~w(invalid_json_schema invalid_response_format unsupported_response_format) or
          Regex.match?(
            ~r/invalid (?:json )?schema|unsupported (?:json )?schema|invalid response_format/,
            message
          ) ->
        "schema"

      code in ~w(connection_error connection_failed request_timeout server_error) or
        (is_integer(status) and status in 500..599) or
          Regex.match?(
            ~r/connection (?:reset|refused|closed)|stream disconnected|error sending request/,
            message
          ) ->
        "transport"

      true ->
        "unknown"
    end
  end

  defp usage(value) when is_map(value) do
    Map.filter(
      Map.take(value, ~w(input_tokens cached_input_tokens output_tokens)),
      fn {_, n} -> is_integer(n) and n >= 0 and n <= 1_000_000_000_000 end
    )
  end

  defp usage(_), do: %{}
end
