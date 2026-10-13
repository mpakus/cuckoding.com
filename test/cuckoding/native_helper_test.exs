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
end
