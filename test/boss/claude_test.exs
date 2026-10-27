defmodule Boss.ClaudeTest do
  use ExUnit.Case, async: true
  alias Boss.Agents.Claude
  alias Boss.Deliveries.Protocol

  @init %{
    "type" => "system",
    "subtype" => "init",
    "tools" => ["StructuredOutput"],
    "mcp_servers" => [],
    "plugins" => [],
    "permissionMode" => "dontAsk"
  }
  @report %{
    "verdict" => "approved",
    "summary" => "Matches saved evidence",
    "acceptance" => [
      %{
        "criterion" => "Create result.txt",
        "status" => "passed",
        "evidence" => "Full diff and check receipt"
      }
    ],
    "issues" => []
  }
  @result %{
    "type" => "result",
    "subtype" => "success",
    "is_error" => false,
    "permission_denials" => [],
    "structured_output" => @report
  }

  test "split JSONL accepts internal formatter but only final structured output is authoritative" do
    messages = [
      @init,
      %{
        "type" => "assistant",
        "message" => %{
          "content" => [
            %{"type" => "text", "text" => "SECRET_SENTINEL"},
            %{
              "type" => "tool_use",
              "id" => "tool1",
              "name" => "StructuredOutput",
              "input" => %{"verdict" => "SECRET_SENTINEL"}
            }
          ]
        }
      },
      %{
        "type" => "user",
        "message" => %{
          "content" => [
            %{"type" => "tool_result", "tool_use_id" => "tool1", "content" => "SECRET_SENTINEL"}
          ]
        }
      },
      Map.put(@result, "usage", %{
        "input_tokens" => 12,
        "output_tokens" => 4,
        "cache_read_input_tokens" => 6,
        "private" => "SECRET_SENTINEL"
      })
    ]

    data = Enum.map_join(messages, &line/1)

    state =
      Enum.reduce(:binary.bin_to_list(data), Claude.new(), fn byte, state ->
        Claude.feed(state, {:stdout, <<byte>>})
      end)

    assert Claude.complete?(state)

    assert {:ok, @report} =
             Protocol.review(state.report, %{"acceptance" => ["Create result.txt"]})

    summary = Claude.summary(state)
    assert summary["event_count"] == 4

    assert summary["usage"] == %{
             "input_tokens" => 12,
             "output_tokens" => 4,
             "cache_read_input_tokens" => 6
           }

    refute inspect(summary) =~ "SECRET_SENTINEL"
    refute inspect(state) =~ "SECRET_SENTINEL"
  end

  test "startup with external tools, plugin, MCP, missing receipt or permission override fails" do
    for init <- [
          Map.put(@init, "tools", ["Bash"]),
          Map.put(@init, "plugins", [%{"name" => "plugin"}]),
          Map.put(@init, "mcp_servers", [%{"name" => "mcp"}]),
          Map.put(@init, "permissionMode", "bypassPermissions"),
          Map.delete(@init, "plugins")
        ] do
      assert parse([init, @result]).error == :unsafe_init
    end

    assert parse([@result]).error == :missing_init
    assert parse([@init, @init]).error == :unsafe_init
  end

  test "external or unrecognized tool messages fail instead of becoming review evidence" do
    for name <- ["Bash", "Read", "mcp__tool", "Agent"] do
      event = %{
        "type" => "assistant",
        "message" => %{"content" => [%{"type" => "tool_use", "name" => name, "id" => "a"}]}
      }

      assert parse([@init, event, @result]).error == :unexpected_tool
    end

    event = %{
      "type" => "user",
      "message" => %{"content" => [%{"type" => "tool_result", "tool_use_id" => "unknown"}]}
    }

    assert parse([@init, event]).error == :unexpected_tool
  end

  test "error, refusal, missing schema result and denied tools never complete" do
    for result <- [
          Map.put(@result, "subtype", "error_max_turns"),
          Map.put(@result, "is_error", true),
          Map.delete(@result, "is_error"),
          Map.delete(@result, "structured_output"),
          Map.put(@result, "structured_output", %{} |> JSON.encode!()),
          Map.put(@result, "permission_denials", [%{"tool_name" => "Bash"}]),
          Map.delete(@result, "permission_denials")
        ] do
      state = parse([@init, result])
      refute Claude.complete?(state)
      assert state.report == nil
    end
  end

  test "duplicate nested report keys survive parsing and existing typed validator rejects them" do
    duplicated =
      ~s({"type":"result","subtype":"success","is_error":false,"permission_denials":[],"structured_output":{"verdict":"changes_requested","verdict":"approved","summary":"s","acceptance":[{"criterion":"Create result.txt","status":"passed","evidence":"e"}],"issues":[]}}\n)

    state = Claude.feed(parse([@init]), {:stdout, duplicated})
    assert Claude.complete?(state)

    assert {:error, :invalid_review} =
             Protocol.review(state.report, %{"acceptance" => ["Create result.txt"]})

    duplicate_type = ~s({"type":"result","type":"assistant"}\n)
    assert Claude.feed(parse([@init]), {:stdout, duplicate_type}).error == :invalid_jsonl
  end

  test "terminal duplication, malformed, truncated and oversized output fail closed" do
    assert parse([@init, @result, @result]).error == :event_after_terminal
    assert parse([@init, @result, %{"type" => "assistant"}]).error == :event_after_terminal

    for data <- ["no json\n", "[]\n", String.duplicate("x", 262_145)] do
      refute Claude.complete?(Claude.feed(Claude.new(), {:stdout, data}))
    end

    state = Claude.feed(parse([@init]), {:stdout, JSON.encode!(@result)})
    refute Claude.complete?(state)
    oversized = put_in(@result["structured_output"]["summary"], String.duplicate("x", 32_768))
    assert parse([@init, oversized]).error == :invalid_result
  end

  test "bounded history, output budget and raw stderr exclusion" do
    event = %{
      "type" => "assistant",
      "message" => %{"content" => [%{"type" => "text", "text" => "SECRET_SENTINEL"}]}
    }

    state = parse([@init | List.duplicate(event, 100)])
    assert length(state.events) == 20 and state.count == 101
    state = Claude.feed(state, {:stderr, "SECRET_SENTINEL"})
    refute inspect(state) =~ "SECRET_SENTINEL"
    assert state.stderr_bytes == 15
    assert Claude.feed(state, {:stderr, String.duplicate("x", 8_388_608)}).error == :output_limit
    assert parse([@init | List.duplicate(event, 4096)]).error == :event_limit
  end

  test "stdin invocation disables external tools without bypass or changing account mode" do
    args = Claude.args()

    for {key, value} <- [
          {"--input-format", "text"},
          {"--output-format", "stream-json"},
          {"--tools", ""},
          {"--permission-mode", "dontAsk"},
          {"--setting-sources", ""},
          {"--mcp-config", ~s({"mcpServers":{}})},
          {"--disallowedTools", "mcp__*"}
        ] do
      assert Enum.at(args, Enum.find_index(args, &(&1 == key)) + 1) == value
    end

    for flag <-
          ~w(--print --verbose --strict-mcp-config --disable-slash-commands --no-session-persistence),
        do: assert(flag in args)

    refute Enum.any?(args, &String.contains?(&1, "bypass"))
    refute "--bare" in args
    settings = Enum.at(args, Enum.find_index(args, &(&1 == "--settings")) + 1) |> JSON.decode!()
    assert settings == %{"disableAllHooks" => true, "autoMemoryEnabled" => false}
    assert {:ok, prompt} = Protocol.prompt(:claude_review, %{"specification" => "Saved source"})
    assert prompt =~ "No repository, shell, web"
    assert prompt =~ "mark it unclear"

    assert {:error, :input_too_large} =
             Protocol.prompt(:claude_review, %{
               "specification" => String.duplicate("x", 1_048_576)
             })
  end

  defp parse(events), do: Claude.feed(Claude.new(), {:stdout, Enum.map_join(events, &line/1)})
  defp line(event), do: JSON.encode!(event) <> "\n"
end
