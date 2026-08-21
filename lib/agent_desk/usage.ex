defmodule AgentDesk.Usage do
  @moduledoc """
  Canonical token/cost samples recorded from normalized provider usage events.
  """

  import Ecto.Query

  alias AgentDesk.Agents.Session
  alias AgentDesk.Ids
  alias AgentDesk.Projects.Project
  alias AgentDesk.Repo
  alias AgentDesk.Usage.Sample

  @spec record(Session.t(), map()) :: {:ok, Sample.t()} | {:error, term()}
  def record(%Session{} = session, payload) when is_map(payload) do
    input = parse_int(payload["input_tokens"] || payload["input"])
    output = parse_int(payload["output_tokens"] || payload["output"])
    total = parse_int(payload["total_tokens"] || payload["total"])
    total = if total == 0, do: input + output, else: total

    %Sample{}
    |> Sample.changeset(%{
      id: Ids.generate(),
      project_id: session.project_id,
      agent_session_id: session.id,
      input_tokens: input,
      output_tokens: output,
      total_tokens: total,
      cost_cents: parse_cost(payload["cost_cents"]),
      model: payload["model"]
    })
    |> Repo.insert()
  end

  @spec summary(Project.t() | Ecto.UUID.t()) :: map()
  def summary(%Project{id: id}), do: summary(id)

  def summary(project_id) when is_binary(project_id) do
    rows =
      Sample
      |> where([s], s.project_id == ^project_id)
      |> select([s], %{
        input: sum(s.input_tokens),
        output: sum(s.output_tokens),
        total: sum(s.total_tokens),
        cost: sum(s.cost_cents)
      })
      |> Repo.one()

    %{
      "input_tokens" => as_int(rows && rows.input),
      "output_tokens" => as_int(rows && rows.output),
      "total_tokens" => as_int(rows && rows.total),
      "cost_cents" => as_int(rows && rows.cost)
    }
  end

  defp as_int(nil), do: 0
  defp as_int(value) when is_integer(value), do: value
  defp as_int(%Decimal{} = value), do: Decimal.to_integer(value)
  defp as_int(_), do: 0

  defp parse_int(value) when is_integer(value) and value >= 0, do: min(value, 1_000_000_000)

  defp parse_int(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} -> parse_int(int)
      _ -> 0
    end
  end

  defp parse_int(_), do: 0

  defp parse_cost(value) when is_integer(value) and value >= 0, do: value
  defp parse_cost(_), do: nil
end
