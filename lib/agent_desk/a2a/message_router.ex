defmodule AgentDesk.A2A.MessageRouter do
  @moduledoc """
  Loads pending inbox rows and records adapter delivery outcomes.

  Adapters never send peer-to-peer; they receive deliveries here and ack after
  a successful safe-boundary injection.
  """

  import Ecto.Query

  alias AgentDesk.A2A
  alias AgentDesk.A2A.Delivery
  alias AgentDesk.A2A.Message
  alias AgentDesk.Agents.Session
  alias AgentDesk.Repo
  alias AgentDesk.Scope

  @spec pending(Ecto.UUID.t()) :: [Delivery.t()]
  def pending(session_id) when is_binary(session_id) do
    Delivery
    |> where([d], d.agent_session_id == ^session_id and d.state == "pending")
    |> order_by([d], asc: d.inbox_sequence)
    |> preload(:message)
    |> Repo.all()
  end

  @spec render_injection([Delivery.t()]) :: String.t()
  def render_injection(deliveries) do
    deliveries
    |> Enum.map_join("\n", fn %Delivery{message: %Message{} = message} ->
      "[A2A ##{message.id}] #{message.body || Jason.encode!(message.parts)}"
    end)
  end

  @spec acknowledge_injected(Session.t(), [Delivery.t()]) :: :ok
  def acknowledge_injected(%Session{} = session, deliveries) do
    project = Repo.get!(AgentDesk.Projects.Project, session.project_id)
    scope = Scope.for_agent(project, session)

    Enum.each(deliveries, fn delivery ->
      _ = A2A.acknowledge(scope, delivery.id)
    end)

    :ok
  end
end
