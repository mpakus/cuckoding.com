defmodule Cuckoding.DataCase do
  @moduledoc false
  use ExUnit.CaseTemplate
  alias Ecto.Adapters.SQL.Sandbox

  using do
    quote do
      alias Cuckoding.Repo
      import Ecto.Query
    end
  end

  setup tags do
    setup_sandbox(tags)
    :ok
  end

  def setup_sandbox(tags) do
    pid = Sandbox.start_owner!(Cuckoding.Repo, shared: not tags[:async])
    on_exit(fn -> Sandbox.stop_owner(pid) end)
  end

  def preview_receipt(paths \\ ["docs/plan.md"]) do
    %{
      "status" => "previewed",
      "preview" => %{
        "branch" => "refs/heads/main",
        "repository" => String.duplicate("a", 64),
        "files" =>
          Enum.map(
            paths,
            &%{
              "path" => &1,
              "bytes" => 8,
              "mode" => "100644",
              "sha256" => String.duplicate("b", 64)
            }
          )
      }
    }
  end

  # A registered Arena projection; draft-board tests never touch its project path.
  def arena_fixture do
    alias Cuckoding.{Arena, Command, Repo, Team}
    id = Ecto.UUID.generate()

    Repo.insert!(%Command{
      id: id,
      kind: "register_arena",
      state: "completed",
      expected_revision: 1
    })

    Repo.insert!(%Arena{
      command_id: id,
      selection_id: id,
      team_revision_id: Team.current().id,
      name: "Test Arena",
      path: "/private/tmp/draft-fixture-#{id}",
      device: 1,
      inode: System.unique_integer([:positive]),
      git_entry: "absent",
      inserted_at: DateTime.utc_now()
    })
  end
end
