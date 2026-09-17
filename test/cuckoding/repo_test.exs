defmodule Cuckoding.RepoTest do
  use Cuckoding.DataCase, async: true

  test "uses the required production SQLite pragmas" do
    assert pragma("journal_mode") == "wal"
    assert pragma("foreign_keys") == 1
    assert pragma("synchronous") == 1

    assert Application.fetch_env!(:cuckoding, Repo)[:busy_timeout] == 5_000
  end

  defp pragma(name) do
    %{rows: [[value]]} = Ecto.Adapters.SQL.query!(Repo, "PRAGMA #{name}", [])
    value
  end
end
