defmodule Boss.ReviewVerdictTest do
  use ExUnit.Case, async: true
  alias Boss.Agents.Codex
  alias Boss.Reviews.Verdict

  defp report(verdict \\ "approved", status \\ "passed", issues \\ []) do
    %{
      "verdict" => verdict,
      "summary" => "Checked the saved requirement.",
      "acceptance" => [%{"criterion" => "Works", "status" => status, "evidence" => "app.ex:1"}],
      "issues" => issues
    }
  end

  defp issue, do: %{"criterion" => "Works", "message" => "Handle the missing value."}
  defp decode(value), do: Verdict.decode(Jason.encode!(value))

  defp event(type, attrs \\ %{}), do: Jason.encode!(Map.put(attrs, "type", type)) <> "\n"

  defp message(text),
    do: event("item.completed", %{"item" => %{"type" => "agent_message", "text" => text}})

  test "accepts bounded consistent verdicts and actionable rejection" do
    for value <- [
          report(),
          report("changes_requested", "failed", [issue()]),
          report("needs_spec_revision", "unclear", [issue()]),
          Map.put(report(), "acceptance", List.duplicate(hd(report()["acceptance"]), 20)),
          report("changes_requested", "failed", List.duplicate(issue(), 20))
        ] do
      assert {:ok, ^value} = decode(value)
    end
  end

  test "rejects missing, unknown, duplicated and trailing JSON fields" do
    good = Jason.encode!(report())

    for text <- [
          "",
          "[]",
          "null",
          good <> " {}",
          "```json\n" <> good <> "\n```",
          "Report: " <> good,
          String.replace(
            good,
            ~s("verdict":"approved"),
            ~s("verdict":"changes_requested","verdict":"approved")
          ),
          String.replace(
            good,
            ~s("verdict":"approved"),
            ~S("verdict":"changes_requested","verd\u0069ct":"approved")
          ),
          String.replace(good, ~s("status":"passed"), ~s("status":"failed","status":"passed")),
          Jason.encode!(Map.delete(report(), "issues")),
          Jason.encode!(Map.put(report(), "extra", true)),
          Jason.encode!(put_in(report(), ["acceptance", Access.at(0), "extra"], true)),
          String.replace(
            Jason.encode!(report("changes_requested", "failed", [issue()])),
            ~s("message":"Handle the missing value."),
            ~s("message":"old","message":"new")
          )
        ] do
      assert {:error, :invalid_review} = Verdict.decode(text)
    end
  end

  test "rejects contradictory verdicts, wrong types and empty evidence" do
    for value <- [
          report("finished"),
          report("approved", "failed"),
          report("approved", "passed", [issue()]),
          report("changes_requested", "passed", [issue()]),
          report("changes_requested", "failed"),
          report("needs_spec_revision", "failed", [issue()]),
          report("needs_spec_revision", "unclear"),
          Map.put(report(), "summary", " \n "),
          Map.put(report(), "issues", %{}),
          Map.put(report(), "acceptance", []),
          put_in(report(), ["acceptance", Access.at(0), "evidence"], ""),
          put_in(report(), ["acceptance", Access.at(0), "status"], true),
          put_in(
            report("changes_requested", "failed", [issue()]),
            ["issues", Access.at(0), "message"],
            " "
          )
        ] do
      assert {:error, :invalid_review} = decode(value)
    end
  end

  test "bounds input bytes, arrays and each report field" do
    good = Jason.encode!(report())
    assert {:ok, _} = Verdict.decode(good <> String.duplicate(" ", 32_768 - byte_size(good)))

    for text <- [<<255>>, String.duplicate(" ", 32_769)] do
      assert {:error, :invalid_review} = Verdict.decode(text)
    end

    for {path, limit} <- [
          {["summary"], 2000},
          {["acceptance", Access.at(0), "criterion"], 1000},
          {["acceptance", Access.at(0), "evidence"], 2000},
          {["issues", Access.at(0), "criterion"], 1000},
          {["issues", Access.at(0), "message"], 2000}
        ] do
      value =
        put_in(
          report("changes_requested", "failed", [issue()]),
          path,
          String.duplicate("a", limit)
        )

      assert {:ok, ^value} = decode(value)

      assert {:error, :invalid_review} =
               decode(put_in(value, path, String.duplicate("é", div(limit, 2) + 1)))
    end

    for {key, item} <- [{"acceptance", hd(report()["acceptance"])}, {"issues", issue()}] do
      assert {:error, :invalid_review} = decode(Map.put(report(), key, List.duplicate(item, 21)))
    end

    large =
      Map.put(
        report(),
        "acceptance",
        List.duplicate(
          %{
            "criterion" => String.duplicate("a", 1000),
            "status" => "passed",
            "evidence" => String.duplicate("a", 2000)
          },
          20
        )
      )

    assert {:error, :invalid_review} = decode(large)
  end

  test "JSONL remains metadata-only and review invocation uses a separate final-output file" do
    data = event("turn.started") <> message("SECRET_SENTINEL") <> event("turn.completed")
    parser = Codex.feed(Codex.new(), {:stdout, data})
    assert Codex.complete?(parser)
    refute inspect(parser) =~ "SECRET_SENTINEL"
    output_path = "/private/review fixture/final.json"
    args = Codex.args(:review, output_path)
    assert "read-only" in args
    refute "workspace-write" in args
    assert "--ephemeral" in args
    assert Enum.take(args, 4) == ["--ask-for-approval", "never", "exec", "--ignore-user-config"]
    assert "--json" in args
    refute "resume" in args
    assert args |> Enum.drop_while(&(&1 != "--sandbox")) |> Enum.at(1) == "read-only"
    assert args |> Enum.drop_while(&(&1 != "--color")) |> Enum.at(1) == "never"
    assert List.last(args) == "-"
    assert args |> Enum.drop_while(&(&1 != "--output-last-message")) |> Enum.at(1) == output_path
    schema = args |> Enum.drop_while(&(&1 != "--output-schema")) |> Enum.at(1)
    assert Path.type(schema) == :absolute

    assert {:ok, %{"additionalProperties" => false, "required" => required}} =
             schema |> File.read!() |> Jason.decode()

    assert Enum.sort(required) == ~w(acceptance issues summary verdict)

    properties = schema |> File.read!() |> Jason.decode!() |> Map.fetch!("properties")
    assert properties["verdict"]["enum"] == ~w(approved changes_requested needs_spec_revision)
    assert properties["acceptance"]["items"]["additionalProperties"] == false
    assert properties["issues"]["items"]["additionalProperties"] == false

    assert Enum.sort(properties["acceptance"]["items"]["required"]) ==
             ~w(criterion evidence status)

    assert Enum.sort(properties["issues"]["items"]["required"]) == ~w(criterion message)
  end
end
