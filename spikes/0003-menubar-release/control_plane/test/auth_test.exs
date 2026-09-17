defmodule CuckodingShellSpike.AuthTest do
  use ExUnit.Case, async: false

  alias CuckodingShellSpike.Auth

  setup do
    path = Path.join(System.tmp_dir!(), "cuckoding-auth-#{System.unique_integer([:positive])}")
    File.write!(path, "#{String.duplicate("s", 64)}\nbootstrap", [:exclusive])
    File.chmod!(path, 0o600)
    System.put_env("CUCKODING_BOOTSTRAP_FILE", path)
    start_supervised!(Auth)
    on_exit(fn -> System.delete_env("CUCKODING_BOOTSTRAP_FILE") end)
    %{path: path}
  end

  test "exchanges bootstrap and consumes browser tokens exactly once", %{path: path} do
    refute File.exists?(path)
    assert {:ok, shell} = Auth.bootstrap("bootstrap")
    assert :error = Auth.bootstrap("bootstrap")
    assert Auth.shell?(shell)
    refute Auth.shell?("invalid")

    assert {:ok, browser} = Auth.browser_token(shell)
    assert Auth.consume_browser_token(browser)
    refute Auth.consume_browser_token(browser)
  end
end
