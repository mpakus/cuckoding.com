defmodule Cuckoding.TaskChecksTest do
  use ExUnit.Case, async: true
  alias Cuckoding.TaskChecks

  defp profile(kind, directory \\ ".", timeout \\ 60),
    do: %{"profile" => kind, "directory" => directory, "timeout_seconds" => timeout}

  test "only closed fixed profiles and bounded relative scopes are valid" do
    assert TaskChecks.valid?([])
    assert TaskChecks.valid?([profile("npm-test"), profile("mix-test", "apps/web")])

    for rows <- [
          nil,
          [profile("shell")],
          [Map.put(profile("npm-test"), "arguments", ["install"])],
          [profile("npm-test", "../other")],
          [profile("mix-test", "/tmp")],
          [profile("mix-test", "a\\b")],
          [profile("mix-test", String.duplicate("x", 241))],
          [profile("npm-test", ".", 0)],
          [profile("mix-test", ".", "60")],
          [profile("mix-test", ".", 301)],
          [profile("npm-test"), profile("npm-test", ".", 30)],
          for(n <- 1..5, do: profile("npm-test", "app#{n}"))
        ] do
      refute TaskChecks.valid?(rows), inspect(rows)
    end
  end

  test "host resolution is stable and literal, never supplied command text" do
    a = %{"id" => Ecto.UUID.generate(), "verification" => [profile("npm-test", "web")]}
    b = %{"id" => Ecto.UUID.generate(), "verification" => [profile("mix-test")]}
    scope = TaskChecks.freeze([a, b], [])
    assert scope == TaskChecks.freeze([a, b], [])
    assert scope["task_verification"]["version"] == "planned-checks-v1"
    [npm, mix] = scope["checks"]
    assert npm["executable"] == "npm"
    assert npm["arguments"] == ["test", "--offline"]
    assert npm["directory"] == "web"
    assert mix["arguments"] == ["test"]
    assert Ecto.UUID.cast(npm["id"]) == {:ok, npm["id"]}
    assert TaskChecks.freeze([Map.delete(a, "verification")], []) == %{"checks" => []}
    configured = %{npm | "id" => Ecto.UUID.generate(), "directory" => "other"}
    [kept, added] = TaskChecks.freeze([a], [configured])["checks"]
    assert kept == configured
    assert added["name"] != kept["name"]
    assert TaskChecks.plan_valid?([a, a, b])
  end

  test "a generated proposal must fit the existing total command and time budgets" do
    oversized =
      for task <- 1..3,
          do: %{
            "id" => to_string(task),
            "verification" =>
              for(check <- 1..3, do: profile("npm-test", "app#{task}-#{check}", 1))
          }

    refute TaskChecks.plan_valid?(oversized)

    over_time = [
      %{
        "verification" => [
          profile("npm-test", "a", 300),
          profile("mix-test", "b", 300),
          profile("npm-test", "c", 1)
        ]
      }
    ]

    refute TaskChecks.plan_valid?(over_time)
    assert TaskChecks.plan_valid?([%{"verification" => [profile("npm-test")]}])

    repeated = [
      %{"verification" => [profile("npm-test", "web")]},
      %{"verification" => [profile("npm-test", "admin")]}
    ]

    assert TaskChecks.plan_valid?(repeated)
    assert TaskChecks.criteria_hash("criteria", nil) == TaskChecks.criteria_hash("criteria", [])

    refute TaskChecks.criteria_hash("criteria", []) ==
             TaskChecks.criteria_hash("criteria", [profile("npm-test")])
  end

  test "bounded form decoding preserves incomplete text but rejects unknown fields" do
    raw = %{
      "profile" => "npm-test",
      "directory" => "web",
      "timeout_seconds" => "60",
      "_unused_directory" => ""
    }

    assert {:ok, [%{"timeout_seconds" => 60}]} = TaskChecks.form(%{"0" => raw})

    assert {:ok, [%{"timeout_seconds" => ""}]} =
             TaskChecks.form(%{"0" => Map.put(raw, "timeout_seconds", "")})

    assert TaskChecks.form(%{"1" => raw}) == :error
    assert TaskChecks.form(%{"0" => Map.put(raw, "arguments", "install")}) == :error
    assert TaskChecks.form(%{"0" => Map.put(raw, "_unused_directory", "foreign")}) == :error
  end

  test "task and final scopes keep configured checks and omit only skipped task profiles" do
    a = %{"id" => Ecto.UUID.generate(), "verification" => [profile("npm-test", "a")]}
    b = %{"id" => Ecto.UUID.generate(), "verification" => [profile("mix-test", "b")]}
    bare = %{"id" => Ecto.UUID.generate()}

    configured = %{
      "id" => Ecto.UUID.generate(),
      "name" => "Always",
      "executable" => "npm",
      "arguments" => ["test", "--offline"],
      "directory" => "common",
      "timeout_seconds" => 60
    }

    snapshot = TaskChecks.freeze([a, b, bare], [configured]) |> Map.put("tasks", [a, b, bare])

    assert TaskChecks.scope(snapshot, a["id"], %{}) |> Enum.map(& &1["directory"]) == [
             "common",
             "a"
           ]

    assert TaskChecks.scope(snapshot, bare["id"], %{}) == [configured]
    integrated = %{"integrated_task_ids" => [a["id"]]}

    assert TaskChecks.scope(snapshot, b["id"], integrated) |> Enum.map(& &1["directory"]) == [
             "common",
             "a",
             "b"
           ]

    omitted = %{"omitted_tasks" => [%{"id" => b["id"], "state" => "skipped"}]}

    assert TaskChecks.scope(snapshot, nil, omitted) |> Enum.map(& &1["directory"]) == [
             "common",
             "a"
           ]

    assert TaskChecks.scope(snapshot, nil, %{}) |> length() == 3
    legacy = Map.delete(snapshot, "task_verification")
    assert TaskChecks.scope(legacy, a["id"], omitted) == snapshot["checks"]
    refute TaskChecks.current?(put_in(snapshot["task_verification"]["configured_ids"], []))
    refute TaskChecks.current?(put_in(snapshot["checks"], []))
    assert TaskChecks.current?(snapshot)
  end
end
