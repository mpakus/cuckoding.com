defmodule Boss.Deliveries.Diagnostics do
  @moduledoc false

  def message("candidate_changed"),
    do:
      "The candidate's files, HEAD or retained ref changed during verification. " <>
        "A successful command exit cannot approve changed content. Inspect the retained worktree " <>
        "and its Git status; generated build/test files need appropriate repository ignore rules " <>
        "before a fresh workflow. Do not ignore source or tests."

  def message(_), do: nil
end
