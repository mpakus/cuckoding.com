defmodule AgentDesk.PathsTest do
  use ExUnit.Case, async: true

  alias AgentDesk.Paths

  test "expands and accepts an existing directory" do
    dir = Path.expand("tmp/path-canon-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)

    assert {:ok, canonical} = Paths.canonicalize(Path.join(dir, "."))
    assert canonical == dir
  after
    File.rm_rf("tmp")
  end

  test "returns not_found for a missing path" do
    assert Paths.canonicalize(
             "/definitely/missing/agentdesk-#{System.unique_integer([:positive])}"
           ) ==
             {:error, :not_found}
  end

  test "returns not_a_directory for a file" do
    file = Path.expand("tmp/path-file-#{System.unique_integer([:positive])}")
    File.mkdir_p!(Path.dirname(file))
    File.write!(file, "x")

    assert Paths.canonicalize(file) == {:error, :not_a_directory}
  after
    File.rm_rf("tmp")
  end
end
