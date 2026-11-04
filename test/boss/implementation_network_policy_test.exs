defmodule Boss.ImplementationNetworkPolicyTest do
  use ExUnit.Case, async: true
  alias Boss.Agents.{Codex, NetworkPolicy}

  @model %{"model" => "gpt-5.6-terra", "reasoning_effort" => "xhigh"}
  @domains ~w(127.0.0.1 builds.hex.pm github.com hex.pm localhost registry.npmjs.org release-assets.githubusercontent.com repo.hex.pm)

  test "version one grants only the fixed package destinations and explicit local binding" do
    policy = NetworkPolicy.profile(1)
    assert NetworkPolicy.current() == 1

    assert policy == %{
             "version" => 1,
             "network_access" => true,
             "proxy" => true,
             "allow_local_binding" => true,
             "domains" => @domains
           }

    argv = Codex.args(:implement, nil, @model, policy)
    assert Enum.take(argv, 10) == Enum.take(Codex.args(), 10)
    assert Enum.at(argv, Enum.find_index(argv, &(&1 == "--sandbox")) + 1) == "workspace-write"
    assert List.last(argv) == "-"
    assert "--ignore-user-config" in argv and "--ephemeral" in argv
    assert "sandbox_workspace_write.network_access=true" in argv
    assert "features.network_proxy.enabled=true" in argv
    assert "features.network_proxy.allow_local_binding=true" in argv

    assert ~s(features.network_proxy.domains={"127.0.0.1"="allow","builds.hex.pm"="allow","github.com"="allow","hex.pm"="allow","localhost"="allow","registry.npmjs.org"="allow","release-assets.githubusercontent.com"="allow","repo.hex.pm"="allow"}) in argv

    refute Enum.any?(argv, &String.contains?(&1, "*"))
    refute "danger-full-access" in argv
  end

  test "legacy argv and all read-only stages retain their original policy" do
    assert NetworkPolicy.profile(0) == nil and NetworkPolicy.profile(nil) == nil
    assert Codex.args(:implement, nil, @model, nil) == Codex.args(:implement, nil, @model)

    for kind <- [:plan, :intake, :resolve, :review] do
      argv = Codex.args(kind, "/tmp/report", @model, nil)
      assert argv == Codex.args(kind, "/tmp/report", @model)
      assert "read-only" in argv

      refute Enum.any?(
               argv,
               &String.starts_with?(&1, ["sandbox_workspace_write.", "features.network_proxy."])
             )

      assert_raise ArgumentError, fn ->
        Codex.args(kind, "/tmp/report", @model, NetworkPolicy.profile(1))
      end
    end
  end

  test "unknown versions, changed hosts and extra fields cannot expand the policy" do
    assert_raise FunctionClauseError, fn -> NetworkPolicy.profile(2) end
    policy = NetworkPolicy.profile(1)

    for changed <- [
          Map.put(policy, "domains", ["*"]),
          Map.put(policy, "extra", true),
          Map.put(policy, "proxy", false),
          Map.put(policy, "version", "1"),
          Map.put(policy, "version", 1.0),
          Map.put(policy, "domains", Enum.reverse(@domains))
        ] do
      refute NetworkPolicy.valid?(changed)
      assert_raise ArgumentError, fn -> Codex.args(:implement, nil, @model, changed) end
    end
  end

  test "resolver and implementer learn the pinned capability without treating it as evidence" do
    policy = NetworkPolicy.profile(1)

    for kind <- [:resolve, :implement] do
      assert {:ok, prompt} =
               Boss.Deliveries.Protocol.prompt(kind, %{"implementation_network_policy" => policy})

      assert prompt =~ "historical network-denial notes"
      assert prompt =~ "not evidence that installation"
      assert prompt =~ "exact locked revision"
      assert prompt =~ "does not grant networking or execution permission"
      assert prompt =~ JSON.encode!(policy)
      assert {:ok, legacy} = Boss.Deliveries.Protocol.prompt(kind, %{})
      refute legacy =~ "BOSS has pinned implementation_network_policy"
    end
  end
end
