defmodule Cuckoding.RepoTest do
  use Cuckoding.DataCase, async: true

  test "uses the required production SQLite pragmas" do
    assert pragma("journal_mode") == "wal"
    assert pragma("foreign_keys") == 1
    assert pragma("synchronous") == 1

    assert Application.fetch_env!(:cuckoding, Repo)[:busy_timeout] == 5_000
  end

  test "enforces one active lease per resource with a partial unique index" do
    %{rows: rows} = Ecto.Adapters.SQL.query!(Repo, "PRAGMA index_list('leases')", [])

    assert Enum.any?(rows, fn [_sequence, name, unique, _origin, partial] ->
             name == "leases_one_active_resource_index" and unique == 1 and partial == 1
           end)
  end

  defp pragma(name) do
    %{rows: [[value]]} = Ecto.Adapters.SQL.query!(Repo, "PRAGMA #{name}", [])
    value
  end
end
