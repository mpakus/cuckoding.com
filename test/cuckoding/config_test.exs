defmodule Cuckoding.ConfigTest do
  use ExUnit.Case, async: true

  test "redacts nested sensitive configuration values" do
    input = %{
      port: 4000,
      secret_key_base: "secret-canary",
      nested: [provider_token: "token-canary", visible: "ok"]
    }

    assert Cuckoding.Config.sanitize(input) == %{
             port: 4000,
             secret_key_base: "[REDACTED]",
             nested: [provider_token: "[REDACTED]", visible: "ok"]
           }
  end

  test "diagnostic snapshot exposes only allowlisted endpoint configuration" do
    snapshot = Cuckoding.Config.safe_snapshot()
    serialized = inspect(snapshot)

    assert snapshot.endpoint.bind == "127.0.0.1"
    refute serialized =~ "secret_key_base"
    refute serialized =~ "secret-canary"
  end

  test "LiveView accepts only the supported loopback origins" do
    assert CuckodingWeb.Endpoint.config(:check_origin) == ["//127.0.0.1", "//localhost"]
  end
end
