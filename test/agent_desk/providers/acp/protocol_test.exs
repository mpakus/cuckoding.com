defmodule AgentDesk.Providers.ACP.ProtocolTest do
  use ExUnit.Case, async: true

  alias AgentDesk.Providers.ACP.Protocol

  test "tool_call carries a title instead of a raw dump" do
    [event] =
      Protocol.from_update(
        %{
          "update" => %{
            "sessionUpdate" => "tool_call",
            "toolCallId" => "call-1",
            "title" => "hub_list_agents",
            "kind" => "other",
            "status" => "pending"
          }
        },
        "cursor"
      )

    assert event.type == :tool_started
    assert event.payload["title"] == "hub_list_agents"
    assert event.payload["tool"] == "hub_list_agents"
  end

  test "failed tool_call_update keeps a human reason" do
    [event] =
      Protocol.from_update(
        %{
          "update" => %{
            "sessionUpdate" => "tool_call_update",
            "toolCallId" => "call-1",
            "status" => "failed",
            "content" => [
              %{"type" => "content", "content" => %{"type" => "text", "text" => "not found"}}
            ]
          }
        },
        "cursor"
      )

    assert event.type == :tool_completed
    assert event.payload["reason"] == "not found"
  end

  test "permission requests never inspect the toolCall map" do
    event =
      Protocol.from_permission(
        3,
        %{"toolCall" => %{"title" => "Edit file", "kind" => "edit"}},
        "cursor"
      )

    assert event.type == :approval_requested
    assert event.payload["summary"] == "Edit file"
    refute event.payload["summary"] =~ "%{"
  end
end
