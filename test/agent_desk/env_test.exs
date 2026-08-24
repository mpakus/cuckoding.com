defmodule AgentDesk.EnvTest do
  use ExUnit.Case, async: true

  alias AgentDesk.Env

  test "merge_path keeps the first occurrence and drops blanks" do
    assert Env.merge_path(["/opt/homebrew/bin:/usr/bin", "/usr/bin:/bin", nil, ""]) ==
             "/opt/homebrew/bin:/usr/bin:/bin"
  end

  test "extra_dirs only includes directories that exist" do
    assert Enum.all?(Env.extra_dirs(), &File.dir?/1)
    assert "/usr/bin" in Env.extra_dirs()
  end
end
