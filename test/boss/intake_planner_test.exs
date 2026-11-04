defmodule Boss.Projects.IntakePlannerTest do
  use ExUnit.Case, async: true

  alias Boss.Projects.Intake.Planner

  @paths ["docs/requirements.md"]

  test "accepts a bounded plan with references to selected documentation" do
    second = task("second", ["first"])
    first = task("first", [])

    assert {:ok, %{"tasks" => [^second, ^first]}} =
             Planner.decode(JSON.encode!(%{"tasks" => [second, first]}), @paths)

    assert {:ok, %{"tasks" => []}} = Planner.decode(~s({"tasks":[]}), @paths)
  end

  test "rejects duplicate JSON keys, unknown paths, and invalid dependencies" do
    assert {:error, :invalid_documentation_plan} =
             Planner.decode(~s({"tasks":[],"tasks":[]}), @paths)

    duplicate = JSON.encode!(task("first", []))
    invalid = ~s({"tasks":[{"id":"extra",#{String.trim_leading(duplicate, "{")}]})

    assert {:error, :invalid_documentation_plan} = Planner.decode(invalid, @paths)

    for tasks <- [
          [task("first", ["missing"])],
          [task("first", ["second"]), task("second", ["first"])],
          [task("first", []), task("first", [])],
          [Map.put(task("first", []), "sources", ["README.md"])],
          [Map.put(task("first", []), "acceptance", [])],
          [Map.put(task("first", []), "command", "mix test")]
        ] do
      assert {:error, :invalid_documentation_plan} =
               Planner.decode(JSON.encode!(%{"tasks" => tasks}), @paths)
    end
  end

  test "diagnoses aggregate bytes before otherwise valid per-task fields" do
    tasks =
      for index <- 1..9,
          do: Map.put(task("task_#{index}", []), "specification", String.duplicate("x", 3900))

    report = JSON.encode!(%{"tasks" => tasks})
    assert byte_size(report) > 32_768
    assert {:error, :report_too_large} = Planner.decode_detailed(report, @paths)
    assert {:error, :invalid_documentation_plan} = Planner.decode(report, @paths)
    assert {:error, :invalid_encoding} = Planner.decode_detailed(<<255>>, @paths)
    assert {:error, :report_empty} = Planner.decode_detailed("", @paths)
    assert {:error, :invalid_json} = Planner.decode_detailed("{", @paths)
  end

  test "fixed validation codes distinguish shape, field, source and graph failures" do
    for {tasks, code} <- [
          {List.duplicate(task("one", []), 33), :task_limit},
          {[task("one", []), task("one", [])], :duplicate_task_id},
          {[task("one", ["two"]), task("two", ["one"])], :dependency_cycle},
          {[task("one", ["missing"])], :invalid_dependencies},
          {[Map.put(task("one", []), "title", String.duplicate("é", 101))], :invalid_title},
          {[Map.put(task("one", []), "specification", String.duplicate("x", 4001))],
           :invalid_specification},
          {[Map.put(task("one", []), "acceptance", for(i <- 1..13, do: "Criterion #{i}"))],
           :invalid_acceptance},
          {[Map.put(task("one", []), "sources", ["docs/private.md"])], :invalid_sources},
          {[Map.put(task("one", []), "extra", "RAW_SECRET_SENTINEL")], :unknown_fields}
        ] do
      assert {:error, ^code} = Planner.decode_detailed(JSON.encode!(%{"tasks" => tasks}), @paths)
    end

    assert {:error, :duplicate_keys} =
             Planner.decode_detailed(~s({"tasks":[],"tasks":[]}), @paths)

    assert {:error, :invalid_shape} = Planner.decode_detailed(~s({"tasks":{}}), @paths)
  end

  test "schema and prompt publish finite limits and recovery keeps only fixed diagnosis" do
    schema = File.read!(Application.app_dir(:boss, "priv/intake_schema.json")) |> JSON.decode!()
    entries = schema["properties"]["tasks"]
    fields = entries["items"]["properties"]
    assert entries["maxItems"] == 32
    assert fields["specification"]["pattern"] == ~S(^[^\u0000]{1,4000}$)
    assert fields["title"]["pattern"] == ~S(^[^\r\n\u0000]{1,200}$)
    assert fields["acceptance"]["maxItems"] == 12
    assert fields["acceptance"]["items"]["pattern"] == ~S(^[^\u0000]{1,500}$)
    assert fields["sources"]["maxItems"] == 8
    assert fields["depends_on"]["maxItems"] == 32
    assert schema["description"] =~ "32768 UTF-8 bytes"
    config = %{"argv" => ["mix", "test"], "timeout_ms" => 5000}

    prior = %{
      "validation_code" => "report_too_large",
      "report_bytes" => 36_000,
      "report" => "RAW_SECRET_SENTINEL"
    }

    assert {:ok, prompt} =
             Planner.prompt("base", %{"docs/requirements.md" => "Original scope"}, config, prior)

    assert prompt =~ "32768 UTF-8 bytes"
    assert prompt =~ "without\ndropping requirements"
    refute prompt =~ "RAW_SECRET_SENTINEL"
    [_, input] = String.split(prompt, "BOSS project intake input (JSON):\n", parts: 2)
    data = JSON.decode!(input)
    assert data["check_config"] == config
    assert data["documents"] == %{"docs/requirements.md" => "Original scope"}
    assert data["previous_failure"] == Map.take(prior, ["validation_code", "report_bytes"])
  end

  defp task(id, dependencies),
    do: %{
      "id" => id,
      "title" => "Implement #{id}",
      "specification" => "Implement the remaining requirement.",
      "acceptance" => ["The requested result is observable."],
      "depends_on" => dependencies,
      "sources" => @paths
    }
end
