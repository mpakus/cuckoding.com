defmodule Cuckoding.SpecificationFixtures do
  @moduledoc false
  alias Cuckoding.{Specifications, Storage, Tabulae}

  def specification_fixture do
    root = "/private/tmp/cuckoding-spec-test-#{Ecto.UUID.generate()}"
    original = Application.get_env(:cuckoding, :data_dir)
    Storage.prepare!(root)
    Application.put_env(:cuckoding, :data_dir, root)

    ExUnit.Callbacks.on_exit(fn ->
      if original,
        do: Application.put_env(:cuckoding, :data_dir, original),
        else: Application.delete_env(:cuckoding, :data_dir)

      File.rm_rf!(root)
    end)

    arena = Cuckoding.DataCase.arena_fixture()
    {:ok, board} = Tabulae.create(Ecto.UUID.generate(), arena.id, "Specifications")
    task = Ecto.UUID.generate()

    attrs = %{
      "title" => "Health endpoint",
      "description" => "Return a local status.",
      "criteria" => "A focused test verifies the response.",
      "column" => "specs",
      "depends_on" => []
    }

    {:ok, _} = Tabulae.save(Ecto.UUID.generate(), arena.id, board.id, task, 0, attrs)
    %{board: board, task: task, attrs: attrs, root: root}
  end

  def request_spec(board, task, revision \\ 1, key \\ Ecto.UUID.generate()) do
    {:ok, preview} = Specifications.preview(board.arena_id, board.id, task, revision)
    Specifications.request(key, board.arena_id, board.id, task, revision, preview["sha256"], true)
  end
end
