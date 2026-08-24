defmodule AgentDesk.Providers.AcpRegistryTest do
  use AgentDesk.DataCase, async: false

  alias AgentDesk.Providers.AcpInstall
  alias AgentDesk.Providers.AcpRegistry
  alias AgentDesk.Repo

  setup do
    :persistent_term.erase({AcpRegistry, :catalog})
    :ok
  end

  test "lists snapshot agents and filters by search" do
    agents = AcpRegistry.list("", "all")
    ids = Enum.map(agents, & &1["id"])
    assert "codex-acp" in ids
    assert "cline" in ids

    matches = AcpRegistry.list("codex", "all")
    assert Enum.all?(matches, &String.contains?(String.downcase(&1["id"] <> &1["name"]), "codex"))
  end

  test "install and remove persist without secrets" do
    assert {:ok, %AcpInstall{} = install} = AcpRegistry.install("cline")
    assert install.status == "installed"
    assert install.provider_key == "acp"
    assert install.executable == "npx"
    assert hd(install.args) == "-y"
    refute inspect(install) =~ "sk-"

    cline = Enum.find(AcpRegistry.list("", "installed"), &(&1["id"] == "cline"))
    assert cline["installed"]

    assert {:ok, removed} = AcpRegistry.remove("cline")
    assert removed.status == "removed"
    refute Enum.any?(AcpRegistry.list("", "installed"), &(&1["id"] == "cline"))
  end

  test "session attrs require an install and keep string registry ids" do
    assert {:error, :not_installed} = AcpRegistry.session_attrs("cline")
    assert {:ok, _} = AcpRegistry.install("cline")
    assert {:ok, attrs} = AcpRegistry.session_attrs("cline")
    assert attrs.provider == "acp"
    assert attrs.settings["acp_registry_id"] == "cline"
    assert is_binary(attrs.settings["acp_registry_id"])
    assert attrs.settings["acp_executable"] == "npx"
  end

  test "unknown registry ids are rejected" do
    assert {:error, :unknown_agent} = AcpRegistry.install("not-a-real-agent")
    assert Repo.aggregate(AcpInstall, :count) == 0
  end
end
