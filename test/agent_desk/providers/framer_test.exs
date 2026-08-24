defmodule AgentDesk.Providers.FramerTest do
  use ExUnit.Case, async: true

  alias AgentDesk.Providers.Framer

  test "buffers partial lines until a newline arrives" do
    framer = Framer.new()
    assert {:ok, [], framer} = Framer.push(framer, "{\"a\":")
    assert {:ok, [~s({"a":1})], _framer} = Framer.push(framer, "1}\n")
  end

  test "skips oversized lines and keeps framing the rest of the stream" do
    framer = Framer.new(max_line: 8)
    assert {:ok, ["ok"], framer} = Framer.push(framer, String.duplicate("x", 9) <> "\nok\n")
    assert framer.dropped >= 1
    assert framer.skipping == false
  end

  test "skips an oversized line that arrives across chunks" do
    framer = Framer.new(max_line: 8)
    assert {:ok, [], framer} = Framer.push(framer, String.duplicate("x", 9))
    assert framer.skipping
    assert {:ok, ["ok"], framer} = Framer.push(framer, "yyyy\nok\n")
    assert framer.skipping == false
    assert framer.dropped >= 1
  end
end
