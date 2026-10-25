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
end
