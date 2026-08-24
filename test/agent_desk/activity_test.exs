defmodule AgentDesk.ActivityTest do
  use ExUnit.Case, async: true

  alias AgentDesk.Activity
  alias AgentDesk.Providers.Event

  test "joins bare tokens with spaces and keeps punctuation tight" do
    assert Activity.join("from", "the") == "from the"
    assert Activity.join("picker", ",") == "picker,"
    assert Activity.join("picker,", " especially") == "picker, especially"
  end

  test "groups consecutive agent deltas into one item" do
    items =
      Activity.coalesce([
        %{id: "1", type: "message_delta", text: "from", payload: %{"text" => "from"}},
        %{id: "2", type: "message_delta", text: "the", payload: %{"text" => "the"}},
        %{id: "3", type: "message_delta", text: "picker", payload: %{"text" => "picker"}},
        %{id: "4", type: "file_change", text: "lib/app.ex", payload: %{"path" => "lib/app.ex"}},
        %{id: "5", type: "message_delta", text: "next", payload: %{"text" => "next"}}
      ])

    assert length(items) == 3
    assert hd(items).id == "1"
    assert hd(items).text == "from the picker"
    assert List.last(items).text == "next"
  end

  test "groups provider events before broadcast" do
    events =
      Activity.coalesce_events([
        Event.new(:message_delta, %{"text" => "Escape"}, "codex"),
        Event.new(:message_delta, %{"text" => "handling"}, "codex"),
        Event.new(:turn_completed, %{"summary" => "done"}, "codex")
      ])

    assert length(events) == 2
    assert hd(events).type == :message_delta
    assert hd(events).payload["text"] == "Escape handling"
  end

  test "completed full text replaces the draft instead of concatenating" do
    items =
      Activity.coalesce([
        %{id: "1", type: "message_delta", text: "Hel", payload: %{"text" => "Hel"}},
        %{
          id: "2",
          type: "message_completed",
          text: "Hello world",
          payload: %{"text" => "Hello world"}
        }
      ])

    assert length(items) == 1
    assert hd(items).text == "Hello world"
    assert hd(items).type == "message_completed"
  end

  test "does not merge a new delta into a completed message" do
    refute Activity.mergeable?(
             %{type: "message_completed", text: "done", payload: %{}},
             %{type: "message_delta", text: "next", payload: %{}}
           )
  end
end
