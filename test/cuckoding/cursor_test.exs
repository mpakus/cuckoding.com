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

  test "large Cursor catalogs keep every variant but reject overflow and late invalid rows" do
    rows =
      for index <- 1..512 do
        %{
          "id" => "model-#{index}",
          "model" => "model-#{index}",
          "name" => "Model #{index}",
          "default" => false,
          "hidden" => false
        }
      end

    normalize = fn models ->
      %{
        "status" => "checked",
        "authorization" => "cursor",
        "catalog_status" => "fresh",
        "models" => models
      }
      |> Jason.encode!()
      |> Cursor.normalize_connection()
    end

    for count <- [256, 512] do
      expected = Enum.take(rows, count)
      assert normalize.(expected)["models"] == expected
    end

    for invalid <- [
          rows ++ [%{hd(rows) | "id" => "overflow"}],
          List.replace_at(rows, 511, hd(rows)),
          List.replace_at(rows, 511, %{List.last(rows) | "id" => "bad\nvalue"})
        ] do
      result = normalize.(invalid)
      assert result["catalog_status"] == "failed"
      refute Map.has_key?(result, "models")
    end
  end
end
