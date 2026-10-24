defmodule Cuckoding.CheckImageTest do
  use Cuckoding.DataCase

  alias Cuckoding.{
    BattleFixtures,
    Battles,
    CheckImage,
    GuestCheckFixtures,
    GuestChecks,
    ProjectChecks
  }

  test "image decoding refuses foreign scope, malformed cleanup and private extras" do
    key = Ecto.UUID.generate()
    image = GuestCheckFixtures.image(key)
    assert CheckImage.decode(Jason.encode!(image), key) == image

    for row <- [
          Map.put(image, "key", Ecto.UUID.generate()),
          Map.put(image, "cleanup_verified", "true"),
          Map.put(image, "raw", "PRIVATE_CANARY"),
          Map.delete(image, "kernel_sha256")
        ] do
      rejected = CheckImage.decode(Jason.encode!(row), key)
      refute rejected["cleanup_verified"]
      refute inspect(rejected) =~ "PRIVATE_CANARY"
    end

    changed = Map.put(image, "spec_sha256", String.duplicate("e", 64))

    assert CheckImage.decode(Jason.encode!(changed), key) == %{
             "status" => "check_image_changed",
             "cleanup_verified" => true
           }

    assert CheckImage.decode("null", key)["cleanup_verified"] == false
  end

  test "only a completed exact admission can supply an image for another Start" do
    %{board: board, check: check} = BattleFixtures.fixture()

    {:ok, _} =
      ProjectChecks.save(
        Ecto.UUID.generate(),
        board.arena_id,
        1,
        [Map.put(check, "executable", "mix")],
        true
      )

    battle = BattleFixtures.start(board)
    {:ok, first} = Battles.claim_next(battle.id)
    image = GuestCheckFixtures.image(first.id)
    assert GuestChecks.enabled?(first.request["snapshot"])
    assert CheckImage.scope?(first, image)
    assert CheckImage.cached() == nil

    {:ok, _} =
      Battles.finish(
        first.id,
        first.claim_token,
        BattleFixtures.result(first, %{"check_image" => image})
      )

    assert CheckImage.cached() == image
    {:ok, _} = Battles.stop(battle.id)
    second = BattleFixtures.start(board)
    {:ok, admission} = Battles.claim_next(second.id)
    assert CheckImage.scope?(admission, image)

    refute CheckImage.scope?(
             admission,
             Map.put(image, "kernel_sha256", String.duplicate("f", 64))
           )

    refute CheckImage.scope?(admission, Map.put(image, "key", Ecto.UUID.generate()))
  end

  test "a first Start accepts the exact prepared image without a previous admission" do
    key = Ecto.UUID.generate()
    image = GuestCheckFixtures.image(key)
    path = Path.join(System.tmp_dir!(), "check-image-helper-#{key}")
    previous = Application.get_env(:cuckoding, :native_helper)

    File.write!(
      path,
      "#!/bin/sh\nread -r request\nprintf '%s\\n' '" <> Jason.encode!(image) <> "'\n"
    )

    File.chmod!(path, 0o700)
    Application.put_env(:cuckoding, :native_helper, path)

    on_exit(fn ->
      if previous,
        do: Application.put_env(:cuckoding, :native_helper, previous),
        else: Application.delete_env(:cuckoding, :native_helper)

      File.rm(path)
    end)

    attempt = %{
      id: key,
      request: %{
        "snapshot" => %{"check_execution" => %{"image_spec_sha256" => CheckImage.spec()}}
      }
    }

    assert CheckImage.cached() == nil
    assert CheckImage.ensure(attempt, fn -> true end) == {:ok, image}
  end
end
