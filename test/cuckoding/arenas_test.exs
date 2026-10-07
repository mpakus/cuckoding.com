defmodule Cuckoding.ArenasTest do
  use Cuckoding.DataCase
  alias Cuckoding.{Arena, Arenas, Command, Event, Foundation, NativeFolder, Team}

  setup do
    root = "/private/tmp/cuckoding-arena-#{Ecto.UUID.generate()}"
    File.mkdir!(root)

    previous =
      for key <- [:discovery_home, :data_dir, :native_helper],
          into: %{},
          do: {key, Application.get_env(:cuckoding, key)}

    Application.put_env(:cuckoding, :discovery_home, Path.join(root, "home"))
    Application.put_env(:cuckoding, :data_dir, Path.join(root, "data"))
    File.mkdir!(Path.join(root, "data"))

    on_exit(fn ->
      Enum.each(previous, fn {key, value} ->
        if is_nil(value),
          do: Application.delete_env(:cuckoding, key),
          else: Application.put_env(:cuckoding, key, value)
      end)

      File.rm_rf!(root)
    end)

    %{root: root}
  end

  test "registration is confirmed, idempotent and freezes the displayed team without touching files",
       %{root: root} do
    folder = Path.join(root, "project")
    File.mkdir!(folder)
    File.write!(Path.join(folder, "plan.md"), "private project canary")
    choice = select(folder)
    assert {:ok, again} = Arenas.choose(choice.id)
    assert again.id == choice.id
    assert Foundation.workspace().revision == 0
    roles = put_in(Team.editable(Team.current()), [Access.at(0), "name"], "Future planner")
    assert {:ok, _} = Team.save(Ecto.UUID.generate(), 1, roles)
    key = Ecto.UUID.generate()
    assert {:error, "invalid_registration"} = Arenas.register(key, choice.id, "Project", false)
    Phoenix.PubSub.subscribe(Cuckoding.PubSub, "foundation")
    assert {:ok, arena} = Arenas.register(key, choice.id, "Project", true)
    assert_receive :updated
    assert {:ok, ^arena} = Arenas.register(key, choice.id, "Project", true)
    assert {:error, :key_conflict} = Arenas.register(key, choice.id, "Other", true)
    assert arena.team_revision_id == 1
    assert arena.git_entry == "absent"

    assert hd(Arenas.list()).team_revision.definition["roles"] |> hd() |> Map.fetch!("name") ==
             "Speculator"

    assert File.ls!(folder) == ["plan.md"]
    assert File.read!(Path.join(folder, "plan.md")) == "private project canary"
    refute inspect(Repo.all(Event)) =~ "private project canary"
    refute inspect(Repo.all(Event)) =~ folder
    assert Repo.aggregate(Arena, :count) == 1
    refute Foundation.pending?()
    assert {:ok, nil} = Foundation.claim()
  end

  test "empty, document, unborn, regular and linked Git metadata remain unverified", %{root: root} do
    for kind <- ~w(empty docs unborn git linked) do
      folder = Path.join(root, kind)
      File.mkdir!(folder)

      case kind do
        "docs" -> File.mkdir!(Path.join(folder, "docs"))
        "unborn" -> File.mkdir!(Path.join(folder, ".git"))
        "git" -> File.write!(Path.join(folder, ".git"), "untrusted gitdir: /outside")
        "linked" -> File.ln_s!("/outside", Path.join(folder, ".git"))
        _ -> :ok
      end

      before = File.ls!(folder)
      choice = select(folder)
      assert {:ok, arena} = Arenas.register(Ecto.UUID.generate(), choice.id, kind, true)

      assert arena.git_entry ==
               if(kind in ~w(empty docs), do: "absent", else: "present_unverified")

      assert File.ls!(folder) == before
    end
  end

  test "duplicates, replaced directories, aliases, traversal and protected roots are refused", %{
    root: root
  } do
    folder = Path.join(root, "project")
    File.mkdir!(folder)
    choice = select(folder)
    assert {:ok, _} = Arenas.register(Ecto.UUID.generate(), choice.id, "Project", true)
    duplicate = select(folder)

    assert {:error, "already_registered"} =
             Arenas.register(Ecto.UUID.generate(), duplicate.id, "Again", true)

    File.rename!(folder, folder <> "-old")
    File.mkdir!(folder)

    assert {:error, "folder_changed"} =
             Arenas.register(Ecto.UUID.generate(), choice.id, "Replacement", true)

    alias_path = Path.join(root, "alias")
    File.ln_s!(folder, alias_path)

    for invalid <- [
          alias_path,
          folder <> "/..",
          root,
          "/",
          "/usr",
          "/private/etc",
          Path.join(root, "home"),
          Path.join(root, "data"),
          Path.join(root, ".ssh"),
          "relative",
          "bad\npath",
          %{}
        ] do
      assert {:error, "invalid_folder"} = Arenas.inspect_folder(invalid)
    end

    File.rmdir!(folder)
    File.ln_s!(folder <> "-old", folder)

    assert {:error, "folder_changed"} =
             Arenas.register(Ecto.UUID.generate(), choice.id, "Alias", true)
  end

  test "cancellation and interrupted claims never accept a late selection or replay", %{
    root: root
  } do
    folder = Path.join(root, "project")
    File.mkdir!(folder)
    {:ok, pending} = Arenas.choose(Ecto.UUID.generate())
    assert {:ok, %{result: "setup_busy"}} = Arenas.choose(Ecto.UUID.generate())
    {:ok, _} = Foundation.cancel_probe(pending.id)
    assert Repo.get!(Command, pending.id).state == "cancelled"
    {:ok, _} = Arenas.choose(Ecto.UUID.generate())
    {:ok, running} = Foundation.claim(1_000)
    {:ok, _} = Foundation.cancel_probe(running.id)
    assert Foundation.pending?()

    assert {:ok, %{state: "cancelled", payload: %{"folder" => nil}}} =
             Foundation.finish(running, %{"status" => "selected", "path" => folder})

    assert {:error, :lost_claim} =
             Foundation.finish(running, %{"status" => "selected", "path" => folder})

    {:ok, _} = Arenas.choose(Ecto.UUID.generate())
    {:ok, running} = Foundation.claim(1_000)
    assert {:ok, %{state: "failed", result: "interrupted"}} = Foundation.claim(137_000)

    assert {:error, :lost_claim} =
             Foundation.finish(running, %{"status" => "selected", "path" => folder})

    assert {:ok, nil} = Foundation.claim(140_000)
    assert Foundation.workspace().revision == 0
  end

  test "native transport accepts only bounded closed results and acknowledges cancellation", %{
    root: root
  } do
    script = Path.join(root, "helper")
    Application.put_env(:cuckoding, :native_helper, script)
    previous = System.get_env("CUCKODING_FOLDER_TEST_CANARY")
    System.put_env("CUCKODING_FOLDER_TEST_CANARY", "test-only-canary")

    on_exit(fn ->
      if previous,
        do: System.put_env("CUCKODING_FOLDER_TEST_CANARY", previous),
        else: System.delete_env("CUCKODING_FOLDER_TEST_CANARY")
    end)

    for output <- ["{\"status\":\"cancelled\"}", "not json", String.duplicate("x", 9_000)] do
      File.write!(script, """
      #!/bin/sh
      [ -z "$CUCKODING_FOLDER_TEST_CANARY" ] || exit 9
      [ "$#" -eq 1 ] && [ "$1" = "--choose-arena-folder" ] || exit 9
      [ "$HOME" = "#{root}/data/runtime-home" ] || exit 9
      [ "$PWD" = "#{root}/data" ] || exit 9
      printf '%s' '#{output}'
      """)

      File.chmod!(script, 0o700)
      {:ok, _} = Arenas.choose(Ecto.UUID.generate())
      {:ok, claim} = Foundation.claim()
      result = NativeFolder.choose(claim)

      assert result["status"] ==
               if(String.starts_with?(output, "{"), do: "cancelled", else: "unavailable")

      assert is_integer(result["elapsed_ms"])
      Foundation.finish(claim, result)
    end

    File.write!(script, "#!/bin/sh\nread -r line\n")
    {:ok, _} = Arenas.choose(Ecto.UUID.generate())
    {:ok, claim} = Foundation.claim()
    task = Task.async(fn -> NativeFolder.choose(claim) end)
    Foundation.cancel_probe(claim.id)
    assert %{"status" => "cancelled"} = Task.await(task)
    Foundation.finish(claim, %{"status" => "cancelled"})
    refute Foundation.pending?()
  end

  defp select(path) do
    {:ok, _} = Arenas.choose(Ecto.UUID.generate())
    {:ok, claim} = Foundation.claim()

    {:ok, choice} =
      Foundation.finish(claim, %{"status" => "selected", "path" => path, "elapsed_ms" => 10})

    assert choice.state == "completed"
    choice
  end
end
