defmodule Cuckoding.TaskChecks do
  @moduledoc "Planned verification profiles; only frozen Start grants run commands."
  alias Cuckoding.{GuestChecks, ProjectChecks}
  @policy "planned-checks-v1"
  @profiles %{
    "npm-test" => {"npm tests", "npm", ["test", "--offline"]},
    "mix-test" => {"Mix tests", "mix", ["test"]}
  }

  def profiles, do: Enum.sort(Map.keys(@profiles))
  def label(profile), do: elem(Map.fetch!(@profiles, profile), 0)

  def valid?(rows) when is_list(rows) and length(rows) <= 4 do
    Enum.all?(rows, &valid_row?/1) and
      length(Enum.uniq_by(rows, &Map.take(&1, ~w(profile directory)))) == length(rows)
  end

  def valid?(_), do: false

  def plan_valid?(tasks) do
    case freeze(tasks, []) do
      %{"checks" => []} -> true
      %{"checks" => checks} -> GuestChecks.declarations_valid?(checks)
      _ -> false
    end
  end

  def form(rows) when is_map(rows) and map_size(rows) <= 4 do
    keys = Enum.map(0..3, &to_string/1) |> Enum.take(map_size(rows))

    if Enum.sort(Map.keys(rows)) == keys do
      result = Enum.map(keys, &form_row(rows[&1]))
      if Enum.all?(result, &is_map/1), do: {:ok, result}, else: :error
    else
      :error
    end
  end

  def form(_), do: :error

  defp form_row(row) when is_map(row) do
    fields = ~w(profile directory timeout_seconds)

    row =
      Enum.reduce(fields, row, fn field, row ->
        unused = "_unused_" <> field
        if row[unused] == "", do: Map.delete(row, unused), else: row
      end)

    if Enum.sort(Map.keys(row)) == Enum.sort(fields) and
         Enum.all?(row, fn {_, value} -> is_binary(value) and byte_size(value) <= 512 end) do
      case Integer.parse(row["timeout_seconds"]) do
        {number, ""} -> Map.put(row, "timeout_seconds", number)
        _ -> row
      end
    end
  end

  defp form_row(_), do: nil

  defp valid_row?(row) when is_map(row) do
    Enum.sort(Map.keys(row)) == ~w(directory profile timeout_seconds) and
      row["profile"] in profiles() and
      is_binary(row["directory"]) and byte_size(row["directory"]) <= 240 and
      is_integer(row["timeout_seconds"]) and row["timeout_seconds"] in 1..300 and
      GuestChecks.declarations_valid?([resolve(row)])
  end

  defp valid_row?(_), do: false

  defp resolve(row) do
    {name, executable, arguments} = Map.fetch!(@profiles, row["profile"])

    %{
      "id" => identifier([row["profile"], row["directory"], row["timeout_seconds"]]),
      "name" => name,
      "executable" => executable,
      "arguments" => arguments,
      "directory" => row["directory"],
      "timeout_seconds" => row["timeout_seconds"]
    }
  end

  # Content identity, never a secret or authorization token.
  defp identifier(value) do
    <<a::48, _::4, b::12, _::2, c::62, _::binary>> =
      :crypto.hash(:sha256, Jason.encode!(value))

    {:ok, id} = Ecto.UUID.load(<<a::48, 8::4, b::12, 2::2, c::62>>)
    id
  end

  def freeze(tasks, configured) do
    cond do
      not Enum.all?(tasks, &valid?(Map.get(&1, "verification", []))) ->
        {:error, "invalid_task_verification"}

      Enum.all?(tasks, &(Map.get(&1, "verification", []) == [])) ->
        %{"checks" => configured}

      true ->
        planned_scope(tasks, configured)
    end
  end

  defp planned_scope(tasks, configured) do
    {checks, membership} =
      Enum.reduce(tasks, {configured, %{}}, fn task, {checks, membership} ->
        {checks, ids} = Enum.reduce(Map.get(task, "verification", []), {checks, []}, &add_check/2)

        {checks, Map.put(membership, task["id"], ids)}
      end)

    %{
      "checks" => checks,
      "task_verification" => %{
        "version" => @policy,
        "configured_ids" => Enum.map(configured, & &1["id"]),
        "tasks" => membership
      }
    }
  end

  defp add_check(row, {checks, ids}) do
    proposed = resolve(row)
    fields = ~w(executable arguments directory timeout_seconds)
    existing = Enum.find(checks, &(Map.take(&1, fields) == Map.take(proposed, fields)))

    if existing,
      do: {checks, ids ++ [existing["id"]]},
      else:
        {checks ++ [Map.put(proposed, "name", check_name(proposed["name"], checks))],
         ids ++ [proposed["id"]]}
  end

  defp check_name(label, checks) do
    used = Enum.map(checks, &String.downcase(String.trim(&1["name"])))

    1..(length(checks) + 1)
    |> Enum.map(&"#{label} · #{&1}")
    |> Enum.find(&(String.downcase(&1) not in used))
  end

  def current?(snapshot) do
    case snapshot["task_verification"] do
      nil ->
        true

      %{"version" => @policy, "configured_ids" => ids} when is_list(ids) ->
        configured = Enum.filter(snapshot["checks"], &(&1["id"] in ids))

        Enum.map(configured, & &1["id"]) == ids and
          freeze(snapshot["tasks"], configured) ==
            Map.take(snapshot, ~w(checks task_verification))

      _ ->
        false
    end
  end

  def scope(snapshot, task_id, context) do
    case snapshot["task_verification"] do
      nil -> snapshot["checks"]
      _ -> planned_checks(snapshot, task_id, context)
    end
  end

  defp planned_checks(snapshot, task_id, context) do
    unless current?(snapshot), do: raise(ArgumentError, "invalid frozen check scope")
    policy = snapshot["task_verification"]

    task_ids =
      if is_nil(task_id) do
        omitted = Enum.map(context["omitted_tasks"] || [], & &1["id"])
        snapshot["tasks"] |> Enum.map(& &1["id"]) |> Enum.reject(&(&1 in omitted))
      else
        Enum.uniq((context["integrated_task_ids"] || []) ++ [task_id])
      end

    ids = policy["configured_ids"] ++ Enum.flat_map(task_ids, &Map.fetch!(policy["tasks"], &1))
    Enum.filter(snapshot["checks"], &(&1["id"] in ids))
  end

  def for_attempt(attempt),
    do: scope(attempt.request["snapshot"], attempt.task_id, attempt.request["context"])

  def review_only?(snapshot, task_id, context),
    do: snapshot["version"] == "arena-loop-v2" and scope(snapshot, task_id, context) == []

  def criteria_hash(criteria, verification) when is_list(verification) and verification != [],
    do: ProjectChecks.digest(%{"criteria" => criteria, "verification" => verification})

  def criteria_hash(criteria, _), do: ProjectChecks.digest(criteria)
end
