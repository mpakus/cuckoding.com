defmodule Cuckoding.ReleaseTest do
  use ExUnit.Case, async: true

  alias Cuckoding.Release

  test "migration plan refuses a database created by a newer application" do
    assert {:error, :database_newer_than_application} =
             Release.migration_plan([
               {:up, 1, "known"},
               {:up, 2, "** FILE NOT FOUND **"}
             ])
  end

  test "migration plan distinguishes clean install, current schema, and required backup" do
    assert :clean_install = Release.migration_plan([{:down, 1, "create"}])
    assert :current = Release.migration_plan([{:up, 1, "create"}])

    assert :backup_required =
             Release.migration_plan([{:up, 1, "create"}, {:down, 2, "change"}])
  end
end
