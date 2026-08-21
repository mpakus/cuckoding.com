defmodule AgentDesk.A2A.Policy do
  @moduledoc """
  Autonomous delegation bounds: depth, fan-out, rate, and part size.
  """

  import Ecto.Query

  alias AgentDesk.A2A.Delegation
  alias AgentDesk.A2A.Task
  alias AgentDesk.Clock
  alias AgentDesk.Repo

  @spec check_delegation(Ecto.UUID.t(), Ecto.UUID.t(), Task.t()) :: :ok | {:error, atom()}
  def check_delegation(project_id, from_agent_id, %Task{} = task) do
    policy = Application.get_env(:agent_desk, :a2a, [])

    with :ok <- check_depth(task, Keyword.get(policy, :max_delegation_depth, 3)),
         :ok <-
           check_fan_out(
             project_id,
             from_agent_id,
             Keyword.get(policy, :max_open_proposals_per_agent, 4)
           ) do
      check_rate(from_agent_id, Keyword.get(policy, :max_delegation_fan_out, 4))
    end
  end

  @spec max_part_bytes() :: pos_integer()
  def max_part_bytes, do: 32_768

  defp check_depth(task, max) do
    if ancestry_depth(task, 0) >= max, do: {:error, :delegation_depth}, else: :ok
  end

  defp ancestry_depth(%Task{parent_task_id: nil}, n), do: n

  defp ancestry_depth(%Task{parent_task_id: parent_id}, n) do
    case Repo.get(Task, parent_id) do
      %Task{} = parent -> ancestry_depth(parent, n + 1)
      nil -> n
    end
  end

  defp check_fan_out(project_id, from_agent_id, max) do
    count =
      Delegation
      |> where(
        [d],
        d.project_id == ^project_id and d.from_agent_id == ^from_agent_id and
          d.status == "proposed"
      )
      |> Repo.aggregate(:count)

    if count >= max, do: {:error, :delegation_fan_out}, else: :ok
  end

  defp check_rate(from_agent_id, max) do
    since = DateTime.add(Clock.utc_now(), -60, :second)

    count =
      Delegation
      |> where([d], d.from_agent_id == ^from_agent_id and d.inserted_at >= ^since)
      |> Repo.aggregate(:count)

    if count >= max * 2, do: {:error, :delegation_rate}, else: :ok
  end
end
