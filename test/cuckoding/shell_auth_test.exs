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
end
