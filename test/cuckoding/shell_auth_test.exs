defmodule Cuckoding.ShellAuthTest do
  use Cuckoding.DataCase
  alias Cuckoding.{BrowserToken, Event, ShellAuth}

  setup do
    bootstrap = String.duplicate("a", 64)
    Supervisor.terminate_child(Cuckoding.Supervisor, ShellAuth)
    Application.put_env(:cuckoding, :bootstrap_hash, ShellAuth.digest(bootstrap))
    {:ok, _} = Supervisor.restart_child(Cuckoding.Supervisor, ShellAuth)
    {:ok, bootstrap: bootstrap}
  end

  test "bootstrap exchanges once, shell tokens cannot authenticate browsers", %{
    bootstrap: bootstrap
  } do
    assert {:error, :unauthorized} = ShellAuth.bootstrap("wrong")
    assert {:ok, shell} = ShellAuth.bootstrap(bootstrap)
    assert {:error, :unauthorized} = ShellAuth.bootstrap(bootstrap)
    assert :ok = ShellAuth.authorize(shell)
    assert {:error, :unauthorized} = ShellAuth.authorize(bootstrap)
    refute ShellAuth.valid_session?(shell)
    evidence = Repo.all(Event) |> Enum.map(&Map.from_struct/1) |> inspect()
    refute evidence =~ shell
    refute evidence =~ bootstrap
  end

  test "handoff replay and expired sessions are refused; only hashes are stored" do
    handoff = ShellAuth.handoff()
    assert {:ok, session} = ShellAuth.exchange(handoff)
    assert {:error, :unauthorized} = ShellAuth.exchange(handoff)
    assert ShellAuth.valid_session?(session.token)
    rows = Repo.all(BrowserToken)
    assert Enum.all?(rows, &(byte_size(&1.digest) == 32))
    refute inspect(rows) =~ session.token
    Repo.update_all(BrowserToken, set: [expires_at: 0])
    refute ShellAuth.valid_session?(session.token)
    handoff = ShellAuth.handoff()
    Repo.update_all(BrowserToken, set: [expires_at: 0])
    assert {:error, :unauthorized} = ShellAuth.exchange(handoff)
  end

  test "auth worker restart cannot resurrect consumed bootstrap", %{bootstrap: bootstrap} do
    assert {:ok, shell} = ShellAuth.bootstrap(bootstrap)
    Supervisor.terminate_child(Cuckoding.Supervisor, ShellAuth)
    {:ok, _} = Supervisor.restart_child(Cuckoding.Supervisor, ShellAuth)
    assert {:error, :unauthorized} = ShellAuth.authorize(shell)
    assert {:error, :unauthorized} = ShellAuth.bootstrap(bootstrap)
  end

  test "native power reports require shell authority, retain only changes and age honestly", %{
    bootstrap: bootstrap
  } do
    assert ShellAuth.power_status().state == "unknown"
    assert {:ok, shell} = ShellAuth.bootstrap(bootstrap)
    assert {:error, :unauthorized} = ShellAuth.authorize("foreign", "held")
    assert {:error, :invalid_power_state} = ShellAuth.authorize(shell, "raw OS error")
    assert ShellAuth.power_status().state == "unknown"
    assert :ok = ShellAuth.authorize(shell, "held")
    assert :ok = ShellAuth.authorize(shell, "held")
    report = ShellAuth.power_status()
    assert report.state == "held" and report.fresh and report.age_seconds == 0
    monotonic = System.monotonic_time(:millisecond)
    stale = ShellAuth.power_status({report.observed_at, monotonic + 15_000})
    refute stale.fresh
    assert stale.state == "held" and stale.age_seconds >= 15
    # A suspended monotonic clock must not make an old post-sleep report recent.
    refute ShellAuth.power_status({DateTime.add(report.observed_at, 16), monotonic}).fresh
    refute ShellAuth.power_status({DateTime.add(report.observed_at, -1), monotonic}).fresh
    assert :ok = ShellAuth.authorize(shell, "unavailable")
    assert :ok = ShellAuth.authorize(shell, "released")
    reports = Repo.all(from e in Event, where: e.kind == "shell.power_observed", order_by: e.id)
    assert Enum.map(reports, & &1.data["state"]) == ~w(held unavailable released)

    assert Enum.all?(
             reports,
             &(Map.keys(&1.data) |> Enum.sort() == ~w(contract lease_seconds state))
           )

    refute inspect(reports) =~ shell
    Supervisor.terminate_child(Cuckoding.Supervisor, ShellAuth)
    {:ok, _} = Supervisor.restart_child(Cuckoding.Supervisor, ShellAuth)
    assert ShellAuth.power_status().state == "unknown"
  end
end
