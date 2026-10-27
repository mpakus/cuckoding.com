defmodule Boss.Agents.Codex do
  @moduledoc "Bounded Codex JSONL metadata. Raw model/tool output is never retained."
  @line_limit 262_144
  @types ~w(thread.started turn.started turn.completed turn.failed error item.started item.updated item.completed)

  def args, do: command_args("workspace-write", [])

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

  defp fail(state, reason), do: %{state | error: reason, buffer: ""}

  defp usage(value) when is_map(value) do
    Map.filter(
      Map.take(value, ~w(input_tokens cached_input_tokens output_tokens)),
      fn {_, n} -> is_integer(n) and n >= 0 and n <= 1_000_000_000_000 end
    )
  end

  defp usage(_), do: %{}
end
