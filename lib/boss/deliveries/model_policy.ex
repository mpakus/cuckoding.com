defmodule Boss.Deliveries.ModelPolicy do
  @moduledoc "Versioned model routing and finite recovery budgets for managed deliveries."

  def current, do: 1

  def max_cycles(1), do: 5
  def max_cycles(version) when version in [nil, 0], do: 3

  # Includes both resolver opinions, replanning, retry preparation and merge verification.
  def max_steps(1), do: 48
  def max_steps(version) when version in [nil, 0], do: 20

  def route(version, kind, cycle, plan \\ nil)
  def route(version, _, _, _) when version in [nil, 0], do: nil

  def route(1, kind, 1, _) when kind in [:resolve, "resolve"],
    do: selection("gpt-6-astra", "xhigh")

  def route(1, kind, 2, _) when kind in [:resolve, "resolve"],
    do: selection("gpt-6.1-sol", "xhigh")

  def route(1, kind, 1, %{"complexity" => "small"}) when kind in [:implement, "implement"],
    do: selection("gpt-6-luna", "medium")

  def route(1, kind, cycle, _)
      when kind in [:implement, "implement"] and cycle in [2, 4],
      do: selection("gpt-6-astra", "xhigh")

  def route(1, kind, cycle, _)
      when kind in [:implement, "implement"] and cycle in [3, 5],
      do: selection("gpt-6.1-sol", "xhigh")

  def route(1, kind, 1, _) when kind in [:implement, "implement"],
    do: selection("gpt-6.1-sol", "high")

  def route(1, kind, _, _)
      when kind in [
             :plan,
             "plan",
             :review,
             "review",
             :merge_review,
             "merge_review",
             :intake,
             "intake"
           ],
      do: selection("gpt-6.1-sol", "high")

  def select(nil, _excluded_models), do: {:ok, nil}

  def select(%{"model" => model} = preferred, excluded_models)
      when model in ["gpt-6-astra", "gpt-6.1-sol", "gpt-6-luna"] and
             is_list(excluded_models) do
    [preferred, selection("gpt-6.1-sol", "xhigh"), selection("gpt-6-astra", "xhigh")]
    |> Enum.uniq_by(& &1["model"])
    |> Enum.find(fn profile -> profile["model"] not in excluded_models end)
    |> case do
      nil -> {:error, :models_exhausted}
      profile -> {:ok, profile}
    end
  end

  defp selection(model, effort), do: %{"model" => model, "reasoning_effort" => effort}
end
