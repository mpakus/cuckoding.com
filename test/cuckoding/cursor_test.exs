defmodule Cuckoding.CursorTest do
  use ExUnit.Case, async: true
  alias Cuckoding.{Codex, Cursor}

  test "version pin and bounded public metadata refuse malformed output and provider crossover" do
    assert Cursor.normalize(~s({"status":"observed","version":"2026.09.15-d2fe57e"}))["status"] ==
             "supported"

    assert Cursor.normalize(~s({"status":"observed","version":"2026.09.16-abcdef0"}))["status"] ==
             "unsupported"

    assert Cursor.normalize(~s({"status":"observed","version":"secret"}))["status"] ==
             "invalid_output"

    row = %{
      "id" => "grok-fixture",
      "model" => "grok-fixture",
      "name" => "Grok",
      "default" => false,
      "hidden" => false
    }

    public = %{
      "status" => "checked",
      "authorization" => "cursor",
      "catalog_status" => "fresh",
      "models" => [row],
      "userInfo" => %{"email" => "secret"},
      "elapsed_ms" => "secret"
    }

    result = public |> Jason.encode!() |> Cursor.normalize_connection()
    assert result["models"] == [row]
    refute inspect(result) =~ "secret"

    for rows <- [[row, row], [%{row | "id" => "bad\nvalue"}], [%{row | "hidden" => "false"}]] do
      assert public
             |> Map.put("models", rows)
             |> Jason.encode!()
             |> Cursor.normalize_connection()
             |> Map.get("catalog_status") == "failed"
    end

    url = "https://cursor.com/loginDeepControl?uuid=fixture"
    assert Codex.valid_login_url?(url, "cursor")
    refute Codex.valid_login_url?(url)
    refute Codex.valid_login_url?("https://cursor.com.evil.test/loginDeepControl", "cursor")
    refute Codex.valid_login_url?("https://cursor.com/loginDeepControl\\evil", "cursor")
  end
end
