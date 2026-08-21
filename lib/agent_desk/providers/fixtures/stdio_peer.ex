defmodule AgentDesk.Providers.Fixtures.StdioPeer do
  @moduledoc false

  @doc """
  Deterministic stdio peer used by CI. Speaks ACP, Codex App Server, Codex exec JSONL, and Claude stream-json.
  """
  def main(args) do
    {opts, rest, _invalid} =
      OptionParser.parse(args,
        strict: [
          crash: :boolean,
          malformed: :boolean,
          approval: :boolean,
          vendor: :string
        ]
      )

    protocol = List.first(rest) || "acp"
    Process.flag(:trap_exit, true)
    :ok = :io.setopts(:standard_io, binary: true, encoding: :latin1)
    state = %{protocol: protocol, opts: opts, buffer: ""}

    cond do
      state.opts[:crash] ->
        System.halt(1)

      state.opts[:malformed] ->
        IO.write(:stdio, "{not-json\n")
        loop(state)

      true ->
        maybe_banner(state)
        loop(state)
    end
  end

  defp maybe_banner(%{protocol: "claude"} = _state) do
    emit(%{"type" => "system", "subtype" => "init", "session_id" => "claude-sess-1"})
  end

  defp maybe_banner(%{protocol: "codex-exec"} = state) do
    emit_codex_exec(state)
    System.halt(0)
  end

  defp maybe_banner(_state), do: :ok

  defp loop(state) do
    case IO.read(:stdio, :line) do
      :eof ->
        maybe_exec_oneshot(state)

      {:error, _} ->
        :ok

      line ->
        line
        |> IO.iodata_to_binary()
        |> String.trim_trailing("\n")
        |> handle_line(state)
        |> loop()
    end
  end

  defp maybe_exec_oneshot(%{protocol: "codex-exec"} = state) do
    emit_codex_exec(state)
  end

  defp maybe_exec_oneshot(_state), do: :ok

  defp handle_line(line, state) do
    cond do
      state.opts[:malformed] ->
        IO.write(:stdio, "{not-json\n")
        state

      state.protocol in ["acp", "cursor-acp", "opencode-acp"] ->
        handle_acp(line, state)

      state.protocol == "codex-app-server" ->
        handle_codex(line, state)

      state.protocol == "claude" ->
        handle_claude(line, state)

      true ->
        state
    end
  end

  defp handle_acp(line, state) do
    case Jason.decode(line) do
      {:ok, msg} -> acp_method(msg, state)
      {:error, _} -> stderr_invalid(state)
    end
  end

  defp acp_method(%{"method" => "initialize", "id" => id}, state) do
    reply(id, %{
      "protocolVersion" => 1,
      "serverInfo" => %{"name" => vendor(state), "version" => "0.0-fixture"},
      "capabilities" => %{"loadSession" => true}
    })

    state
  end

  defp acp_method(%{"method" => "initialized"}, state), do: state

  defp acp_method(%{"method" => "session/new", "id" => id}, state) do
    reply(id, %{"sessionId" => "sess-fixture-1"})
    state
  end

  defp acp_method(%{"method" => "session/load", "id" => id, "params" => params}, state) do
    reply(id, %{"sessionId" => params["sessionId"] || "sess-fixture-1"})
    state
  end

  defp acp_method(%{"method" => "session/prompt", "id" => id}, state) do
    notify("session/update", %{
      "update" => %{
        "sessionUpdate" => "agent_message_chunk",
        "content" => %{"type" => "text", "text" => "hello from #{vendor(state)}"}
      }
    })

    maybe_permission(state)

    notify("session/update", %{
      "update" => %{"sessionUpdate" => "file_edit", "path" => "lib/app.ex"}
    })

    reply(id, %{"stopReason" => "end_turn"})
    state
  end

  defp acp_method(%{"method" => "session/cancel", "id" => id}, state) do
    reply(id, %{})
    state
  end

  defp acp_method(%{"method" => "session/configure_mcp", "id" => id}, state) do
    reply(id, %{})
    state
  end

  defp acp_method(%{"method" => "cursor/unknown", "id" => id}, state) do
    error(id, -32_601, "Unsupported method cursor/unknown")
    state
  end

  defp acp_method(_msg, state), do: state

  defp handle_codex(line, state) do
    case Jason.decode(line) do
      {:ok, msg} -> codex_method(msg, state)
      {:error, _} -> stderr_invalid(state)
    end
  end

  defp codex_method(%{"method" => "initialize", "id" => id}, state) do
    reply(id, %{"threadId" => nil, "protocolVersion" => "fixture"})
    state
  end

  defp codex_method(%{"method" => "initialized"}, state), do: state

  defp codex_method(%{"method" => "thread/start", "id" => id}, state) do
    reply(id, %{"threadId" => "thread-fixture-1"})
    state
  end

  defp codex_method(%{"method" => "thread/resume", "id" => id, "params" => params}, state) do
    reply(id, %{"threadId" => params["threadId"]})
    state
  end

  defp codex_method(%{"method" => "turn/start", "id" => id}, state) do
    notify("item/agentMessage/delta", %{"delta" => "hello from codex"})
    notify("item/fileChange", %{"path" => "lib/app.ex"})
    maybe_codex_approval(state)
    reply(id, %{"turnId" => "turn-1"})
    notify("turn/completed", %{"turnId" => "turn-1"})
    state
  end

  defp codex_method(%{"method" => "turn/interrupt", "id" => id}, state) do
    reply(id, %{})
    state
  end

  defp codex_method(%{"method" => "session/configure_mcp", "id" => id}, state) do
    reply(id, %{})
    state
  end

  defp codex_method(_msg, state), do: state

  defp stderr_invalid(state) do
    IO.write(:stderr, "invalid json\n")
    state
  end

  defp handle_claude(line, state) do
    case Jason.decode(line) do
      {:ok, %{"type" => "user"}} ->
        if state.opts[:crash], do: System.halt(1)

        emit(%{
          "type" => "system",
          "subtype" => "init",
          "session_id" => "claude-sess-1"
        })

        emit(%{
          "type" => "assistant",
          "message" => %{"content" => [%{"type" => "text", "text" => "hello from claude"}]}
        })

        emit(%{"type" => "result", "session_id" => "claude-sess-1", "subtype" => "success"})
        state

      {:ok, %{"type" => "control", "subtype" => "interrupt"}} ->
        emit(%{"type" => "result", "subtype" => "interrupted"})
        state

      {:ok, _} ->
        state

      {:error, _} ->
        IO.write(:stderr, "invalid json\n")
        state
    end
  end

  defp emit_codex_exec(_state) do
    emit(%{"type" => "thread.started", "thread_id" => "thread-exec-1"})
    emit(%{"type" => "item.agent_message.delta", "delta" => "hello from exec"})
    emit(%{"type" => "item.completed", "item" => "message"})
    emit(%{"type" => "turn.completed"})
  end

  defp maybe_permission(state) do
    if state.opts[:approval] do
      emit_raw(%{
        "jsonrpc" => "2.0",
        "id" => 9001,
        "method" => "session/request_permission",
        "params" => %{"action" => "run", "summary" => "ls"}
      })
    end
  end

  defp maybe_codex_approval(state) do
    if state.opts[:approval] do
      emit_raw(%{
        "jsonrpc" => "2.0",
        "id" => 9001,
        "method" => "approval/request",
        "params" => %{"action" => "run", "summary" => "ls"}
      })
    end
  end

  defp vendor(state), do: state.opts[:vendor] || "acp-fixture"

  defp reply(id, result) do
    emit_raw(%{"jsonrpc" => "2.0", "id" => id, "result" => result})
  end

  defp error(id, code, message) do
    emit_raw(%{
      "jsonrpc" => "2.0",
      "id" => id,
      "error" => %{"code" => code, "message" => message}
    })
  end

  defp notify(method, params) do
    emit_raw(%{"jsonrpc" => "2.0", "method" => method, "params" => params})
  end

  defp emit(map), do: emit_raw(map)

  defp emit_raw(map) do
    IO.binwrite(:stdio, Jason.encode!(map) <> "\n")
  rescue
    ErlangError -> :ok
  end
end
