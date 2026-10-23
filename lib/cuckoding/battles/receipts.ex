defmodule Cuckoding.Battles.Receipts do
  @moduledoc "Attempt-bound receipt evidence; callers retain transaction and workflow authority."
  import Ecto.Query
  alias Cuckoding.Battles.{Attempt, Snapshot, Stages, Waves}
  alias Cuckoding.{LocalGit, Repo, TaskTurn}

  @envelope ~w(battle_id request_id task_id stage criteria_sha256)
  @result_fields @envelope ++
                   ~w(status reason summary feedback head candidate_sha preparation native_candidate native_battle resolved_checks checks provider cleanup_verified)

  # Payload checks do not replace the closed envelope or confer settlement authority.
  def rejected_payload_valid?(_, %{"status" => "cancelled", "cleanup_verified" => cleanup}),
    do: is_boolean(cleanup)

  def rejected_payload_valid?(attempt, result), do: payload_valid?(attempt, result)

  def payload_valid?(_, %{"status" => "failed", "reason" => reason}),
    do: is_binary(reason) and byte_size(reason) in 1..200

  def payload_valid?(%Attempt{role: role} = attempt, result) when not is_nil(role),
    do: provider_valid?(attempt, result)

  def payload_valid?(%Attempt{stage: "admission"} = attempt, %{"status" => "admitted"} = result),
    do:
      sha?(result["head"]) and is_map(result["native_battle"]) and
        resolved_checks?(attempt, result["resolved_checks"])

  def payload_valid?(%Attempt{stage: "prepare_worktree"}, %{"status" => "prepared"} = result),
    do: is_map(result["preparation"])

  def payload_valid?(%Attempt{stage: "combine"} = attempt, %{"status" => "combined"} = result) do
    candidate = result["native_candidate"]
    context = attempt.request["task_context"]

    expected = %{
      "status" => "candidate_combined",
      "key" => attempt.id,
      "battle_key" => attempt.battle_id,
      "worktree_key" => context["preparation"]["key"],
      "task_candidate_key" => context["native_candidate"]["key"],
      "base" => attempt.request["context"]["head"],
      "task_base" => context["preparation"]["head"]
    }

    Waves.enabled?(attempt.request["snapshot"]) and is_map(candidate) and
      LocalGit.normalize(candidate) == candidate and
      Map.take(candidate, Map.keys(expected)) == expected and
      result["candidate_sha"] == candidate["candidate"]
  end

  def payload_valid?(%Attempt{stage: "capture"} = attempt, %{"status" => "captured"} = result) do
    candidate = result["native_candidate"]
    basic = sha?(result["candidate_sha"]) and is_map(candidate)

    if Stages.writers?(attempt.request["snapshot"]) do
      preparation = attempt.request["task_context"]["preparation"]

      basic and LocalGit.normalize(candidate) == candidate and
        candidate["status"] == "candidate_captured" and candidate["key"] == attempt.id and
        candidate["worktree_key"] == preparation["key"] and
        candidate["base"] == preparation["head"] and
        result["candidate_sha"] == candidate["candidate"]
    else
      basic
    end
  end

  def payload_valid?(%Attempt{stage: stage} = attempt, %{"status" => "passed"} = result)
      when stage in ~w(checks final_checks),
      do: candidate?(attempt, result) and checks?(attempt, result["checks"])

  def payload_valid?(
        %Attempt{stage: stage} = attempt,
        %{"status" => "checks_failed", "cleanup_verified" => true} = result
      )
      when stage in ~w(checks final_checks),
      do: candidate?(attempt, result) and failed_checks?(attempt, result["checks"])

  def payload_valid?(
        %Attempt{stage: "integrate"} = attempt,
        %{"status" => "integrated"} = result
      ),
      do:
        candidate?(attempt, result) and result["head"] == result["candidate_sha"] and
          is_map(result["native_battle"])

  def payload_valid?(_, _), do: false

  def provider_valid?(attempt, result) do
    provider = result["provider"] || %{}
    normalized = TaskTurn.normalize(Jason.encode!(provider))

    allowed =
      if(attempt.stage in ~w(secutor final_secutor),
        do: ~w(completed changes_requested blocked),
        else: ~w(completed blocked)
      )

    normalized["status"] == "task_finished" and normalized == provider and
      result["status"] in allowed and
      provider_identity?(attempt, provider) and
      provider["report"]["outcome"] == result["status"] and fresh_session?(attempt, provider) and
      review_candidate?(attempt, result)
  end

  defp review_candidate?(%Attempt{stage: stage} = attempt, result)
       when stage in ~w(secutor final_secutor),
       do: candidate?(attempt, result) and review_verdict?(attempt, result)

  defp review_candidate?(_, _), do: true

  defp review_verdict?(attempt, %{"status" => "completed"} = result) do
    context =
      if(attempt.task_id, do: attempt.request["task_context"], else: attempt.request["context"])

    if Snapshot.task_review_only?(attempt.request["snapshot"]),
      do: is_nil(context["checks"]) and inspected?(result["provider"]["tools"]),
      else: checks?(attempt, context["checks"])
  end

  defp review_verdict?(_, _), do: true

  defp inspected?(tools) when is_list(tools),
    do:
      Enum.any?(tools, &(&1["tool"] in ~w(list_files read_file) and &1["status"] == "completed"))

  defp inspected?(_), do: false

  defp provider_identity?(attempt, provider) do
    role = attempt.request["role"]

    expected = %{
      "request_id" => attempt.id,
      "requested_model" => role["model"],
      "observed_model" => role["model"],
      "effort" => role["effort"],
      "access" => Stages.access(attempt.request["snapshot"], attempt.stage)
    }

    Map.take(provider, Map.keys(expected)) == expected and
      Stages.report_valid?(attempt.request["snapshot"], attempt.stage, attempt.role, provider) and
      provider["transport"] == if(role["kind"] == "cursor", do: "cursor-acp-v1", else: nil)
  end

  defp fresh_session?(attempt, provider) do
    not Repo.exists?(
      from a in Attempt,
        where:
          a.battle_id == ^attempt.battle_id and a.id != ^attempt.id and
            (fragment("json_extract(?, '$.provider.thread_id')", a.result) ==
               ^provider["thread_id"] or
               fragment("json_extract(?, '$.provider.turn_id')", a.result) == ^provider["turn_id"])
    )
  end

  defp checks?(attempt, checks) when is_list(checks) do
    declared = attempt.request["snapshot"]["checks"]

    declared != [] and length(checks) == length(declared) and Enum.all?(checks, &is_map/1) and
      Enum.sort(Enum.map(checks, & &1["id"])) == Enum.sort(Enum.map(declared, & &1["id"])) and
      Enum.all?(checks, &(&1["status"] == "passed" and &1["exit_code"] == 0))
  end

  defp checks?(_, _), do: false

  defp failed_checks?(attempt, checks) when is_list(checks) and checks != [] do
    declared = attempt.request["snapshot"]["checks"]

    Enum.all?(checks, &is_map/1) and length(checks) <= length(declared) and
      Enum.map(checks, & &1["id"]) ==
        declared |> Enum.take(length(checks)) |> Enum.map(& &1["id"]) and
      Enum.all?(Enum.drop(checks, -1), &(&1["status"] == "passed" and &1["exit_code"] == 0)) and
      failed_check?(List.last(checks))
  end

  defp failed_checks?(_, _), do: false

  defp failed_check?(%{"status" => "failed", "exit_code" => code}),
    do: is_integer(code) and code in 1..255

  defp failed_check?(_), do: false

  defp resolved_checks?(attempt, resolved) when is_list(resolved) do
    declared = attempt.request["snapshot"]["checks"]

    (declared != [] or Snapshot.task_review_only?(attempt.request["snapshot"])) and
      length(declared) == length(resolved) and Enum.all?(resolved, &is_map/1) and
      Enum.map(
        resolved,
        &Map.take(&1, ~w(id name executable arguments directory timeout_seconds))
      ) == declared
  end

  defp resolved_checks?(_, _), do: false

  defp candidate?(attempt, result) do
    expected =
      if(attempt.task_id,
        do: attempt.request["task_context"]["candidate_sha"],
        else: attempt.request["context"]["head"]
      )

    sha?(expected) and result["candidate_sha"] == expected
  end

  def bound?(attempt, result, extra \\ [])

  def bound?(attempt, result, extra) when is_map(result) do
    Map.keys(result) -- (@result_fields ++ extra) == [] and
      Map.take(result, @envelope) == Map.take(attempt.request, @envelope) and
      match?({:ok, _}, Jason.encode(result)) and byte_size(Jason.encode!(result)) <= 131_072
  end

  def bound?(_, _, _), do: false

  defp sha?(value), do: is_binary(value) and Regex.match?(~r/\A[0-9a-f]{40}\z/, value)
end
