defmodule Boss.Agents.Claude do
  @moduledoc "Bounded, evidence-only Claude review protocol; no raw stream is retained."
  @line_limit 262_144
  @output_limit 8_388_608

  def args do
    [
      "--print",
      "--input-format",
      "text",
      "--output-format",
      "stream-json",
      "--verbose",
      "--json-schema",
      File.read!(Application.app_dir(:boss, "priv/review_schema.json")),
      "--tools",
      "",
      "--permission-mode",
      "dontAsk",
      "--setting-sources",
      "",
      "--settings",
      ~s({"disableAllHooks":true,"autoMemoryEnabled":false}),
      "--strict-mcp-config",
      "--mcp-config",
      ~s({"mcpServers":{}}),
      "--disallowedTools",
      "mcp__*",
      "--disable-slash-commands",
      "--no-session-persistence"
    ]
  end

  def new do
    %{
      buffer: "",
      count: 0,
      events: [],
      stdout_bytes: 0,
      stderr_bytes: 0,
      started: false,
      terminal: false,
      error: nil,
      usage: %{},
      report: nil,
      tools: MapSet.new()
    }
  end

  def feed(state, {stream, bytes}) when stream in [:stdout, :stderr] do
    key = if stream == :stdout, do: :stdout_bytes, else: :stderr_bytes
    state = Map.update!(state, key, &(&1 + byte_size(bytes)))

    cond do
      state.stdout_bytes + state.stderr_bytes > @output_limit -> fail(state, :output_limit)
      state.error || stream == :stderr -> state
      true -> lines(state, state.buffer <> bytes)
    end
  end

  def feed(state, _), do: state

  def complete?(state),
    do: state.started and state.terminal and is_nil(state.error) and state.buffer == ""

  def summary(state) do
    %{
      "events" => Enum.reverse(state.events),
      "event_count" => state.count,
      "stdout_bytes" => state.stdout_bytes,
      "stderr_bytes" => state.stderr_bytes,
      "usage" => state.usage
    }
  end

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
  defp event(%{terminal: true} = state, _), do: fail(state, :event_after_terminal)
  defp event(%{count: count} = state, _) when count >= 4096, do: fail(state, :event_limit)

  defp event(state, line) do
    with {:ok, decoded} <- Jason.decode(line, objects: :ordered_objects),
         {:ok, event} <- object(decoded) do
      dispatch(state, event)
    else
      _ -> fail(state, :invalid_jsonl)
    end
  end

  defp dispatch(state, %{"type" => "system", "subtype" => "init"} = event) do
    if not state.started and event["tools"] in [[], ["StructuredOutput"]] and
         event["mcp_servers"] == [] and event["plugins"] == [] and
         event["permissionMode"] == "dontAsk" do
      %{record(state, "system.init") | started: true}
    else
      fail(state, :unsafe_init)
    end
  end

  defp dispatch(%{started: false} = state, _), do: fail(state, :missing_init)

  defp dispatch(state, %{"type" => "assistant", "message" => message} = event) do
    with nil <- event["error"],
         {:ok, message} <- object(message),
         content when is_list(content) <- message["content"] do
      Enum.reduce_while(content, record(state, "assistant"), fn block, state ->
        case object(block) do
          {:ok, %{"type" => "tool_use", "name" => "StructuredOutput", "id" => id}}
          when is_binary(id) and byte_size(id) in 1..200 ->
            {:cont, %{state | tools: MapSet.put(state.tools, id)}}

          {:ok, %{"type" => type}} when type in ["text", "thinking", "redacted_thinking"] ->
            {:cont, state}

          _ ->
            {:halt, fail(state, :unexpected_tool)}
        end
      end)
    else
      _ -> fail(state, :agent_error)
    end
  end

  defp dispatch(state, %{"type" => "user", "message" => message}) do
    with {:ok, message} <- object(message),
         content when is_list(content) <- message["content"] do
      Enum.reduce_while(content, record(state, "user"), fn block, state ->
        with {:ok, %{"type" => "tool_result", "tool_use_id" => id}} <- object(block),
             true <- MapSet.member?(state.tools, id) do
          {:cont, %{state | tools: MapSet.delete(state.tools, id)}}
        else
          _ -> {:halt, fail(state, :unexpected_tool)}
        end
      end)
    else
      _ -> fail(state, :invalid_jsonl)
    end
  end

  defp dispatch(state, %{"type" => "rate_limit_event", "rate_limit_info" => info}) do
    with {:ok, info} <- object(info),
         status when status in ["allowed", "allowed_warning"] <- info["status"] do
      record(state, "rate_limit_event")
    else
      _ -> fail(state, :rate_limit)
    end
  end

  defp dispatch(state, %{"type" => "result"} = event) do
    with "success" <- event["subtype"],
         false <- event["is_error"],
         true <- event["stop_reason"] in [nil, "end_turn", "tool_use", "stop_sequence"],
         true <- event["terminal_reason"] in [nil, "completed"],
         nil <- event["deferred_tool_use"],
         [] <- event["permission_denials"],
         %Jason.OrderedObject{} = report <- event["structured_output"],
         text = Jason.encode!(report),
         true <- byte_size(text) <= 32_768 do
      %{record(state, "result") | terminal: true, report: text, usage: usage(event["usage"])}
    else
      _ -> fail(record(state, "result"), :invalid_result)
    end
  end

  defp dispatch(state, _), do: fail(state, :unexpected_event)

  defp object(%Jason.OrderedObject{values: pairs}) do
    keys = Enum.map(pairs, &elem(&1, 0))
    if length(keys) == length(Enum.uniq(keys)), do: {:ok, Map.new(pairs)}, else: :error
  end

  defp object(_), do: :error

  defp usage(value) do
    case object(value) do
      {:ok, value} ->
        Map.filter(
          Map.take(
            value,
            ~w(input_tokens output_tokens cache_read_input_tokens cache_creation_input_tokens)
          ),
          fn {_, n} -> is_integer(n) and n >= 0 and n <= 1_000_000_000_000 end
        )

      _ ->
        %{}
    end
  end

  defp record(state, type),
    do: %{
      state
      | count: state.count + 1,
        events: Enum.take([%{"type" => type, "sequence" => state.count + 1} | state.events], 20)
    }

  defp fail(state, reason),
    do: %{state | error: reason, buffer: "", report: nil, tools: MapSet.new()}
end
