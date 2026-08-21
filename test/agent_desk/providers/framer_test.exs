defmodule AgentDesk.Providers.FramerTest do
  use ExUnit.Case, async: true

  alias AgentDesk.Providers.Framer

  test "buffers partial lines until a newline arrives" do
    framer = Framer.new()
    assert {:ok, [], framer} = Framer.push(framer, "{\"a\":")
    assert {:ok, [~s({"a":1})], _framer} = Framer.push(framer, "1}\n")
  end

  test "rejects oversized lines" do
    framer = Framer.new(max_line: 8)
    assert {:error, :line_too_large} = Framer.push(framer, String.duplicate("x", 9))
  end
end
