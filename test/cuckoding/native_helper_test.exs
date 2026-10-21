defmodule Cuckoding.NativeHelperTest do
  use ExUnit.Case, async: false
  alias Cuckoding.NativeHelper

  setup do
    old = Application.get_env(:cuckoding, :native_helper)
    path = Path.join(System.tmp_dir!(), "cc-helper-#{Ecto.UUID.generate()}")
    Application.put_env(:cuckoding, :native_helper, path)

    on_exit(fn ->
      if old,
        do: Application.put_env(:cuckoding, :native_helper, old),
        else: Application.delete_env(:cuckoding, :native_helper)

      File.rm(path)
    end)

    %{path: path}
  end

  test "revoked authority never launches a helper, even when its path is unavailable" do
    assert %{"status" => "cancelled", "cleanup_verified" => true} =
             NativeHelper.request(nil, [], 1_000, &Jason.decode!/1, 8192,
               active?: fn -> false end
             )
  end

  test "zero exit on cancellation preserves explicit cleanup uncertainty", %{path: path} do
    receipt =
      Jason.encode!(%{
        "status" => "cleanup_uncertain",
        "cleanup_verified" => false,
        "checks" => []
      })

    File.write!(path, "#!/bin/sh\nread -r ignored\nprintf '%s\\n' '" <> receipt <> "'\n")
    File.chmod!(path, 0o700)
    counter = :atomics.new(1, [])
    active = fn -> :atomics.add_get(counter, 1, 1) < 3 end

    assert %{"status" => "cleanup_uncertain", "cleanup_verified" => false} =
             NativeHelper.request(nil, [], 1_000, &Jason.decode!/1, 8192, active?: active)
  end

  test "a verified cancellation acknowledgement can finish Stop", %{path: path} do
    File.write!(
      path,
      "#!/bin/sh\nread -r ignored\nprintf '%s\\n' '{\"status\":\"cancelled\",\"cleanup_verified\":true}'\n"
    )

    File.chmod!(path, 0o700)
    counter = :atomics.new(1, [])
    active = fn -> :atomics.add_get(counter, 1, 1) < 3 end

    assert %{"status" => "cancelled", "cleanup_verified" => true} =
             NativeHelper.request(nil, [], 1_000, &Jason.decode!/1, 8192, active?: active)
  end

  test "provider normalization cannot promote false or malformed closure on cancellation", %{
    path: path
  } do
    for cleanup <- [false, "true"] do
      receipt = Jason.encode!(%{"status" => "cancelled", "cleanup_verified" => cleanup})
      File.write!(path, "#!/bin/sh\nread -r ignored\nprintf '%s\\n' '" <> receipt <> "'\n")
      File.chmod!(path, 0o700)
      counter = :atomics.new(1, [])
      active = fn -> :atomics.add_get(counter, 1, 1) < 3 end

      assert %{"status" => "cleanup_uncertain", "cleanup_verified" => false} =
               NativeHelper.request(nil, [], 1_000, &Cuckoding.Codex.normalize_connection/1, 8192,
                 active?: active
               )
    end
  end

  test "unverified native receipts cannot publish version, account, model, plan or task success" do
    for normalize <- [
          &Cuckoding.Codex.normalize/1,
          &Cuckoding.Cursor.normalize/1,
          &Cuckoding.Codex.normalize_connection/1,
          &Cuckoding.Cursor.normalize_connection/1,
          &Cuckoding.Codex.normalize_model_check/1,
          &Cuckoding.Planning.normalize/1,
          &Cuckoding.TaskTurn.normalize/1
        ] do
      for cleanup <- [false, "true"] do
        result =
          normalize.(
            Jason.encode!(%{
              "status" => "observed",
              "version" => "0.146.0",
              "cleanup_verified" => cleanup,
              "private" => "hidden"
            })
          )

        assert result["status"] in ~w(cleanup_uncertain invalid_output)
        assert result["cleanup_verified"] == false
        refute Map.has_key?(result, "version")
        refute Map.has_key?(result, "private")
      end
    end

    assert %{"status" => "supported"} =
             Cuckoding.Codex.normalize(~s({"status":"observed","version":"0.146.0"}))
  end

  test "closure inspection retains provider duration separately from the helper read", %{
    path: path
  } do
    alias Cuckoding.Battles.ProviderClosure

    attempt = %{
      id: Ecto.UUID.generate(),
      request: %{"role" => %{"agent_id" => "codex", "kind" => "codex"}}
    }

    native =
      ProviderClosure.binding_for(attempt)
      |> Map.take(~w(attempt_sha256 agent_id kind))
      |> Map.merge(%{
        "status" => "provider_closed",
        "request_id" => attempt.id,
        "cleanup_verified" => true,
        "pid" => 1,
        "spawned_at_ms" => 1000,
        "elapsed_ms" => 12_345,
        "receipt_sha256" => String.duplicate("a", 64)
      })

    File.write!(
      path,
      "#!/bin/sh\nread -r ignored\nprintf '%s\\n' '" <> Jason.encode!(native) <> "'\n"
    )

    File.chmod!(path, 0o700)
    assert ProviderClosure.inspect(attempt, fn -> true end) == native

    assert ProviderClosure.inspect(attempt, fn -> false end) == %{
             "status" => "closure_unavailable",
             "cleanup_verified" => false
           }
  end
end
