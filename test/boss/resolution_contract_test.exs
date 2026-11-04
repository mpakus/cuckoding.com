defmodule Boss.ResolutionContractTest do
  use ExUnit.Case, async: true
  alias Boss.Deliveries.Protocol

  @report %{
    "summary" => "Fix the boundary",
    "steps" => ["Check before reading"],
    "assumptions" => [],
    "external_action" => nil
  }

  test "resolution diagnostics retain the exact aggregate byte boundary without truncation" do
    base = %{
      @report
      | "summary" => "x",
        "steps" => List.duplicate(String.duplicate("x", 2000), 16)
    }

    for bytes <- [32_767, 32_768, 32_769] do
      report =
        Map.put(base, "summary", String.duplicate("x", 1 + bytes - byte_size(JSON.encode!(base))))

      text = JSON.encode!(report)
      assert byte_size(text) == bytes
      assert byte_size(report["summary"]) <= 2000

      if bytes <= 32_768 do
        assert {:ok, ^report} = Protocol.resolution_detailed(text)
        assert {:ok, ^report} = Protocol.resolution(text)
      else
        assert {:error, :report_too_large} = Protocol.resolution_detailed(text)
        assert {:error, :invalid_resolution} = Protocol.resolution(text)
      end
    end
  end

  test "field limits count UTF-8 bytes, with unchanged valid boundaries" do
    for {key, count, code} <- [
          {"summary", 1000, :invalid_summary},
          {"steps", 1000, :invalid_steps},
          {"assumptions", 500, :invalid_assumptions},
          {"external_action", 250, :invalid_external_action}
        ] do
      for excess <- ["", "x"] do
        value = String.duplicate("é", count) <> excess
        value = if key in ["steps", "assumptions"], do: [value], else: value
        report = Map.put(@report, key, value)

        if excess == "" do
          assert {:ok, ^report} = Protocol.resolution_detailed(JSON.encode!(report))
        else
          assert {:error, ^code} = Protocol.resolution_detailed(JSON.encode!(report))
        end
      end
    end
  end

  test "fixed diagnostics distinguish malformed structure, missing fields and invalid fields" do
    cases = [
      {"", :report_empty},
      {<<255>>, :invalid_encoding},
      {"{} trailing", :invalid_json},
      {"[]", :invalid_shape},
      {JSON.encode!(Map.delete(@report, "summary")), :invalid_shape},
      {JSON.encode!(Map.put(@report, "secret", "RAW_SECRET_SENTINEL")), :unknown_fields},
      {String.replace(JSON.encode!(@report), "{", ~s({"summary":"overwrite",), global: false),
       :duplicate_keys}
    ]

    for {text, code} <- cases do
      assert {:error, ^code} = Protocol.resolution_detailed(text)
      assert {:error, :invalid_resolution} = Protocol.resolution(text)
    end

    for {field, code} <- [
          {"summary", :invalid_summary},
          {"steps", :invalid_steps},
          {"assumptions", :invalid_assumptions},
          {"external_action", :invalid_external_action}
        ],
        value <- [" ", "\0", true, %{}] do
      value = if field in ["steps", "assumptions"], do: [value], else: value

      assert {:error, ^code} =
               Protocol.resolution_detailed(JSON.encode!(Map.put(@report, field, value)))
    end

    for {key, minimum, code} <- [
          {"steps", 1, :invalid_steps},
          {"assumptions", 0, :invalid_assumptions}
        ],
        count <- [0, 1, 20, 21] do
      report = Map.put(@report, key, List.duplicate("step", count))

      if count in minimum..20,
        do: assert({:ok, ^report} = Protocol.resolution_detailed(JSON.encode!(report))),
        else: assert({:error, ^code} = Protocol.resolution_detailed(JSON.encode!(report)))
    end
  end

  test "producer schema and prompt advertise byte budgets and supported structural bounds" do
    schema =
      File.read!(Application.app_dir(:boss, "priv/resolution_schema.json")) |> JSON.decode!()

    assert schema["description"] =~ "32768 UTF-8 bytes"
    assert Enum.sort(schema["required"]) == ~w(assumptions external_action steps summary)
    assert schema["additionalProperties"] == false
    assert schema["properties"]["steps"]["minItems"] == 1
    assert schema["properties"]["steps"]["maxItems"] == 20
    assert schema["properties"]["assumptions"]["minItems"] == 0
    assert schema["properties"]["assumptions"]["maxItems"] == 20

    for {path, limit} <- [
          {["summary"], 2000},
          {["steps", "items"], 2000},
          {["assumptions", "items"], 1000},
          {["external_action"], 500}
        ] do
      field = get_in(schema["properties"], path)
      assert field["description"] =~ "#{limit} UTF-8 bytes"
      assert is_binary(field["pattern"])
      pattern = Regex.compile!(field["pattern"], "u")
      assert Regex.match?(pattern, String.duplicate("x", limit))
      refute Regex.match?(pattern, String.duplicate("x", limit + 1))
      refute Regex.match?(pattern, "\0")
      refute Map.has_key?(field, "maxLength")
    end

    assert {:ok, prompt} = Protocol.prompt(:resolve, %{"evidence" => "complete original input"})

    for phrase <- [
          "32768 UTF-8 bytes",
          "2000",
          "1000",
          "500",
          "1–20",
          "0–20",
          "including JSON",
          "Do not truncate"
        ],
        do: assert(prompt =~ phrase)

    assert prompt =~ "complete original input"
  end
end
