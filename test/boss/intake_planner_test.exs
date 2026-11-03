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
