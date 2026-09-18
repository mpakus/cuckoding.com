defmodule Cuckoding.Shell.AuthTest do
  use ExUnit.Case, async: false

  alias Cuckoding.Shell.Auth

  test "calls fail closed when desktop authentication is not running" do
    refute Auth.enabled?()
    assert :error = Auth.bootstrap("missing")
    assert :error = Auth.browser_token("missing")
    refute Auth.consume_browser_token("missing")
    refute Auth.shell?("missing")
  end

  test "bootstrap and browser tokens are single use and the file is deleted" do
    path = bootstrap_file(0o600)
    start_supervised!({Auth, path})

    refute File.exists?(path)
    assert {:ok, shell} = Auth.bootstrap(bootstrap_token())
    assert :error = Auth.bootstrap(bootstrap_token())
    assert Auth.shell?(shell)
    refute Auth.shell?("invalid")

    assert {:ok, browser} = Auth.browser_token(shell)
    assert Auth.consume_browser_token(browser)
    refute Auth.consume_browser_token(browser)
    assert :error = Auth.browser_token("invalid")
  end

  test "rejects a credential file readable by other users" do
    path = bootstrap_file(0o644)
    assert {:error, {:invalid_bootstrap_file, _child}} = start_supervised({Auth, path})
  end

  test "rejects a symlinked credential file" do
    target = bootstrap_file(0o600)
    path = target <> "-link"
    File.ln_s!(target, path)

    assert {:error, {:invalid_bootstrap_file, _child}} = start_supervised({Auth, path})
  end

  defp bootstrap_file(mode) do
    directory =
      Path.join(System.tmp_dir!(), "cuckoding-shell-auth-#{System.unique_integer([:positive])}")

    File.mkdir_p!(directory)
    on_exit(fn -> File.rm_rf!(directory) end)

    path = Path.join(directory, "bootstrap")
    File.write!(path, String.duplicate("s", 128) <> "\n" <> bootstrap_token(), [:exclusive])
    File.chmod!(path, mode)
    path
  end

  defp bootstrap_token, do: String.duplicate("b", 64)
end
