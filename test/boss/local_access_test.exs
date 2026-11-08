defmodule Boss.LocalAccessTest do
  use ExUnit.Case, async: true

  test "token is single-use, wrong attempts do not consume it, and session validates" do
    access =
      start_supervised!({Boss.LocalAccess, name: nil, token: "test-token", announce: false})

    assert :error = Boss.LocalAccess.exchange("wrong", access)
    assert :error = Boss.LocalAccess.exchange(nil, access)
    assert {:ok, session} = Boss.LocalAccess.exchange("test-token", access)
    assert Boss.LocalAccess.valid_session?(session, access)
    refute Boss.LocalAccess.valid_session?("fake", access)
    refute Boss.LocalAccess.valid_session?(nil, access)
    assert :error = Boss.LocalAccess.exchange("test-token", access)
  end

  test "issuing a replacement invalidates the old token but keeps established sessions" do
    access = start_supervised!({Boss.LocalAccess, name: nil, token: "first", announce: false})
    assert {:ok, session} = Boss.LocalAccess.exchange("first", access)
    replacement = Boss.LocalAccess.new_token(access)
    assert Boss.LocalAccess.valid_session?(session, access)
    assert :error = Boss.LocalAccess.exchange("first", access)
    assert {:ok, ^session} = Boss.LocalAccess.exchange(replacement, access)
  end

  test "expired bootstrap tokens cannot authorize a browser" do
    access =
      start_supervised!(
        {Boss.LocalAccess, name: nil, token: "test-token", ttl_ms: 0, announce: false}
      )

    assert :error = Boss.LocalAccess.exchange("test-token", access)
  end

  @tag :tmp_dir
  test "a durable credential has a server-side expiry and stores only its digest", %{tmp_dir: dir} do
    opts = [name: nil, data_dir: dir, token: "test-token"]
    {:ok, access} = Boss.LocalAccess.start_link(opts)
    assert {:ok, session, credential, max_age} = Boss.LocalAccess.remember("test-token", access)
    assert :error = Boss.LocalAccess.exchange("test-token", access)
    assert {:ok, ^session} = Boss.LocalAccess.restore(credential, access)
    GenServer.stop(access)

    path = Path.join(dir, ".remembered-browser")
    assert %{mode: mode} = File.stat!(path)
    assert Bitwise.band(mode, 0o777) == 0o600
    assert <<expires_at::64, digest::binary-size(32)>> = File.read!(path)
    assert digest == :crypto.hash(:sha256, credential)
    assert_in_delta expires_at, System.os_time(:second) + max_age, 2

    File.write!(path, <<1::64, digest::binary>>)
    {:ok, restarted} = Boss.LocalAccess.start_link(opts)
    assert :error = Boss.LocalAccess.restore(credential, restarted)
    GenServer.stop(restarted)
  end

  @tag :tmp_dir
  test "a storage failure keeps the one-use token available", %{tmp_dir: dir} do
    File.mkdir!(Path.join(dir, ".remembered-browser"))

    access =
      start_supervised!({Boss.LocalAccess, name: nil, data_dir: dir, token: "test-token"})

    assert {:error, :remember_failed} = Boss.LocalAccess.remember("test-token", access)
    assert {:ok, _session} = Boss.LocalAccess.exchange("test-token", access)
    assert File.ls!(dir) == [".remembered-browser"]
  end
end
