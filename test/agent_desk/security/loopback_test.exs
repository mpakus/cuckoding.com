defmodule AgentDesk.Security.LoopbackTest do
  use ExUnit.Case, async: true

  alias AgentDesk.Security.Loopback

  test "the HTTP endpoint is configured for loopback" do
    assert Loopback.loopback?(Loopback.endpoint_ip())
  end

  test "the Mix release disables Erlang distribution" do
    env = File.read!("rel/env.sh.eex")
    assert env =~ "RELEASE_DISTRIBUTION"
    assert env =~ "none"
  end
end
