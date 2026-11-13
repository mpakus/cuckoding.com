defmodule Boss.Deliveries.Diagnostics do
  @moduledoc false

  def message("candidate_changed"),
    do:
      "The candidate's files, HEAD or retained ref changed during verification. " <>
        "A successful command exit cannot approve changed content. Inspect the retained worktree " <>
        "and its Git status; generated build/test files need appropriate repository ignore rules " <>
        "before a fresh workflow. Do not ignore source or tests."

  def message("command_unavailable"),
    do:
      "The saved check executable is unavailable. Install or select the project toolchain, then start a fresh workflow."

  def message("target_changed"),
    do:
      "The target branch changed before this stage. Inspect its current commit, then start a fresh workflow."

  def message("catalog_unavailable"),
    do:
      "Codex could not return its model catalog. No inference was started. Check the installed CLI, then start again."

  def message("catalog_invalid"),
    do:
      "Codex returned an unsupported model catalog. No model was guessed and no inference was started. Update the CLI or its adapter before retrying."

  def message("catalog_insufficient_models"),
    do:
      "The Codex catalog does not offer two supported coding models for independent diagnosis. No inference was started."

  def message("provider_auth"),
    do:
      "The selected agent rejected authentication. This workflow stopped before another task. Sign in to that agent, then start again."

  def message("provider_rate_limit"),
    do:
      "The selected agent reported a quota, usage, or credit limit. This workflow stopped before another model call. Retry after capacity is available."

  def message("provider_schema"),
    do:
      "The selected agent rejected the structured request configuration. This workflow stopped before another model call. Repair the adapter before retrying."

  def message("provider_transport"),
    do:
      "The selected agent could not complete its transport or event protocol. This workflow stopped before another model call. Check CLI compatibility and connectivity before retrying."

  def message(_), do: nil

  def provider_message(code, agent_id, step_reason \\ nil) do
    actor = agent_label(agent_id)
    detail = sanitized_agent_note(step_reason)
    suffix = if detail, do: " (#{detail})", else: ""

    case code do
      "provider_auth" ->
        "#{actor} rejected authentication#{suffix}. This workflow stopped before another task. Sign in to #{actor}, then start again."

      "provider_rate_limit" ->
        "#{actor} reported a quota, usage, or credit limit#{suffix}. This workflow stopped before another model call. Retry after capacity is available."

      "provider_schema" ->
        "#{actor} rejected the structured request configuration#{suffix}. This workflow stopped before another model call. Repair the adapter before retrying."

      "provider_transport" ->
        "#{actor} could not complete its transport or event protocol#{suffix}. This workflow stopped before another model call. Check CLI compatibility and connectivity before retrying."

      other ->
        message(other)
    end
  end

  def repair_stop(prefix, %{"kind" => "review", "report" => report}),
    do:
      "#{prefix} #{finding(report)} Next: fix the reported issue and verify the corrected candidate."

  def repair_stop(prefix, %{"kind" => "checks", "exit_code" => exit}),
    do:
      "#{prefix} Checks exited #{exit}. Next: reproduce the saved command in the retained checkout, fix the failure, then retry."

  def clarification(report),
    do:
      "#{finding(report)} Next: clarify the authoritative task specification, sync it, and adopt the new revision before retrying."

  def planning_question(question),
    do:
      "Planning needs a decision. #{concise(question)} Next: answer in the task specification, sync and adopt the new revision."

  def step_failure(kind, receipt) do
    stage = stage_name(kind)

    case receipt["outcome"] do
      "timeout" ->
        "#{stage} timed out. Next: inspect the retained workspace and address slow or interactive work before retrying."

      "output_limit" ->
        "#{stage} exceeded its output limit. Next: reduce command verbosity or split the work, then retry."

      "invalid_report" ->
        "#{stage} returned an invalid report. Next: inspect the task requirements and retry the workflow."

      "command_unavailable" ->
        message("command_unavailable")

      _ ->
        note = if is_binary(receipt["reason"]), do: String.trim(receipt["reason"]), else: ""

        cond do
          note != "" and is_integer(receipt["exit_code"]) and receipt["exit_code"] != 0 ->
            "#{stage} exited #{receipt["exit_code"]}. #{note}"

          note != "" ->
            "#{stage}. #{note}"

          is_integer(receipt["exit_code"]) and receipt["exit_code"] != 0 ->
            "#{stage} exited #{receipt["exit_code"]}. Next: inspect the saved stage and verify its CLI or check command before retrying."

          true ->
            "#{stage} stopped before verification. Next: inspect its saved receipt and retained worktree before retrying."
        end
    end
  end

  # Older receipts are immutable. Show a more useful message when the saved
  # evidence describes the terminal decision.
  def attention(reason, steps, delivery \\ nil) do
    case {reason, List.last(steps)} do
      {"The saved specification needs clarification. Original source retained.",
       %{kind: "review", receipt: %{"report" => %{"verdict" => "needs_spec_revision"} = report}}} ->
        clarification(report)

      {prefix,
       %{kind: "review", receipt: %{"report" => %{"verdict" => "changes_requested"} = report}}}
      when prefix in [
             "The same failure repeated for unchanged candidate content. No further automatic attempt.",
             "The three-cycle implementation/check/review budget is exhausted."
           ] ->
        repair_stop(prefix, %{"kind" => "review", "report" => report})

      {prefix, %{kind: "check", receipt: %{"outcome" => "checks_failed", "exit_code" => exit}}}
      when prefix in [
             "The same failure repeated for unchanged candidate content. No further automatic attempt.",
             "The three-cycle implementation/check/review budget is exhausted."
           ] ->
        repair_stop(prefix, %{"kind" => "checks", "exit_code" => exit})

      {"Delivery stage failed validation or execution. Retained evidence requires attention.",
       %{kind: kind, status: status, receipt: receipt}}
      when status in ["failed", "interrupted"] ->
        step_failure(kind, receipt)

      {reason, %{kind: kind, status: "failed", receipt: receipt}}
      when is_binary(reason) ->
        cond do
          String.starts_with?(reason, "Codex reported a quota or rate limit.") ->
            provider_message(
              "provider_rate_limit",
              stage_agent_id(delivery, kind),
              receipt["reason"]
            )

          String.starts_with?(reason, "Codex rejected the structured request") ->
            provider_message(
              "provider_schema",
              stage_agent_id(delivery, kind),
              receipt["reason"]
            )

          String.starts_with?(reason, "Codex could not complete its transport") ->
            provider_message(
              "provider_transport",
              stage_agent_id(delivery, kind),
              receipt["reason"]
            )

          String.contains?(reason, "exited") ->
            step_failure(kind, receipt)

          true ->
            reason
        end

      {reason, %{kind: kind, status: "interrupted", receipt: receipt}}
      when is_binary(reason) ->
        if String.contains?(reason, "exited"), do: step_failure(kind, receipt), else: reason

      _ ->
        reason
    end
  end

  def stage_agent_id(nil, _kind), do: nil

  def stage_agent_id(delivery, kind) when kind in ["review", "merge_review"],
    do: Map.get(delivery, :reviewer)

  def stage_agent_id(delivery, "resolve"),
    do: Map.get(delivery, :analytic) || "codex"

  def stage_agent_id(delivery, kind) when kind in ["plan", "implement"],
    do: Map.get(delivery, :implementer) || "codex"

  def stage_agent_id(_delivery, _kind), do: nil

  defp agent_label("cursor"), do: "Cursor Agent"
  defp agent_label("claude"), do: "Claude Code"
  defp agent_label("opencode"), do: "OpenCode"
  defp agent_label("codex"), do: "Codex"
  defp agent_label(_), do: "The selected agent"

  defp sanitized_agent_note(text) when is_binary(text) do
    trimmed = String.trim(text)

    if String.starts_with?(trimmed, ["Cursor Agent: ", "Claude Code: ", "OpenCode: "]) do
      concise(trimmed)
    end
  end

  defp sanitized_agent_note(_), do: nil

  defp finding(%{"issues" => [%{"message" => message} | rest]}) when is_binary(message) do
    suffix = if rest == [], do: "", else: " (+#{length(rest)} in review)"
    "Review: #{concise(message)}#{suffix}."
  end

  defp finding(_), do: "Review requires more evidence."

  defp concise(message) do
    line =
      String.replace(message, ~r/[\p{Cc}\s]+/u, " ") |> String.trim() |> String.trim_trailing(".")

    if byte_size(line) <= 300 do
      line
    else
      line
      |> String.codepoints()
      |> Enum.reduce_while({[], 0}, fn char, {chars, bytes} ->
        next = bytes + byte_size(char)
        if next <= 297, do: {:cont, {[char | chars], next}}, else: {:halt, {chars, bytes}}
      end)
      |> elem(0)
      |> Enum.reverse()
      |> IO.iodata_to_binary()
      |> Kernel.<>("…")
    end
  end

  defp stage_name("plan"), do: "Planning"
  defp stage_name("resolve"), do: "Diagnosis"
  defp stage_name("implement"), do: "Implementation"
  defp stage_name("review"), do: "Review"
  defp stage_name(kind) when kind in ["check", "retry_check", "post_check"], do: "Checks"
  defp stage_name(_), do: "Workflow stage"
end
