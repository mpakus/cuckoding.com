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

  def message(_), do: nil

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
        if is_integer(receipt["exit_code"]) and receipt["exit_code"] != 0 do
          "#{stage} exited #{receipt["exit_code"]}. Next: inspect the saved stage and verify its CLI or check command before retrying."
        else
          "#{stage} stopped before verification. Next: inspect its saved receipt and retained worktree before retrying."
        end
    end
  end

  # Older receipts are immutable. Show a more useful message when the saved
  # evidence describes the terminal decision.
  def attention(reason, steps) do
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

      _ ->
        reason
    end
  end

  defp finding(%{"issues" => [%{"message" => message} | rest]}) when is_binary(message) do
    suffix = if rest == [], do: "", else: " (+#{length(rest)} in review)"
    "Review: #{concise(message)}#{suffix}."
  end

  defp finding(_), do: "Review requires more evidence."

  defp concise(message) do
    line = String.replace(message, ~r/\s+/u, " ") |> String.trim() |> String.trim_trailing(".")

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
  defp stage_name("implement"), do: "Implementation"
  defp stage_name("review"), do: "Review"
  defp stage_name(kind) when kind in ["check", "retry_check", "post_check"], do: "Checks"
  defp stage_name(_), do: "Workflow stage"
end
