defmodule Cuckoding.BuildInfoTest do
  use ExUnit.Case, async: true
  alias Cuckoding.BuildInfo
  import Cuckoding.BuildInfoFixtures

  test "only closed public metadata for the exact application is accepted" do
    value = info()
    assert {:ok, ^value} = BuildInfo.validate(value)

    for bad <- [
          Map.put(value, "credential", "never display"),
          Map.put(value, "build_id", "invalid"),
          Map.put(value, "source_revision", "/private/path"),
          Map.put(value, "source_dirty", "false"),
          Map.put(value, "target", "other"),
          Map.put(value, "application", "future"),
          Map.put(value, "built_at", "unknown"),
          Map.put(value, "rust", "1.97.1\nprivate"),
          Map.put(value, "schema", 0),
          Map.delete(value, "source_sha256"),
          nil
        ] do
      assert {:error, :invalid_build_info} = BuildInfo.validate(bad)
    end
  end

  test "packaged startup requires the exact embedded UUID/digest and no source fallback" do
    value = info()
    bytes = Jason.encode!(value)
    sha = :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower)
    assert BuildInfo.decode!(bytes, value["build_id"], sha) == value
    assert_raise RuntimeError, fn -> BuildInfo.decode!(bytes, Ecto.UUID.generate(), sha) end
    assert_raise RuntimeError, fn -> BuildInfo.decode!(bytes, nil, sha) end
    assert_raise RuntimeError, fn -> BuildInfo.decode!(bytes, value["build_id"], nil) end

    assert_raise RuntimeError, fn ->
      BuildInfo.decode!(
        Jason.encode!(Map.put(value, "source_dirty", false)),
        value["build_id"],
        sha
      )
    end

    assert_raise RuntimeError, fn ->
      BuildInfo.decode!(String.duplicate("x", 4097), value["build_id"], sha)
    end

    assert_raise RuntimeError, fn -> BuildInfo.load!(value["build_id"], sha) end
  end
end
