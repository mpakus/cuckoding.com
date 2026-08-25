defmodule AgentDesk.A2A.MessageRouter do
  @moduledoc """
  Loads pending inbox rows and records adapter delivery outcomes.

  Adapters never send peer-to-peer. A successful live-port injection marks
  deliveries `injected`; `acknowledged` is reserved for an explicit agent ack.
  """

  import Ecto.Query

  alias AgentDesk.A2A.Delivery
  alias AgentDesk.A2A.Message
  alias AgentDesk.Agents.Session
  alias AgentDesk.Clock
  alias AgentDesk.Repo

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

  @spec mark_injected(Session.t(), [Delivery.t()]) :: :ok
  def mark_injected(%Session{} = session, deliveries) do
    now = Clock.utc_now()
    ids = Enum.map(deliveries, & &1.id)

    Delivery
    |> where(
      [d],
      d.id in ^ids and d.agent_session_id == ^session.id and d.state == "pending"
    )
    |> Repo.update_all(
      set: [state: "injected", injected_at: now, last_error: nil, updated_at: now],
      inc: [attempt_count: 1]
    )

    :ok
  end

  @spec mark_injection_failed(Session.t(), [Delivery.t()], term()) :: :ok
  def mark_injection_failed(%Session{} = session, deliveries, reason) do
    now = Clock.utc_now()
    ids = Enum.map(deliveries, & &1.id)
    error = reason |> inspect() |> String.slice(0, 1_000)

    Delivery
    |> where(
      [d],
      d.id in ^ids and d.agent_session_id == ^session.id and d.state == "pending"
    )
    |> Repo.update_all(set: [last_error: error, updated_at: now], inc: [attempt_count: 1])

    :ok
  end

  @spec mark_interrupted(Ecto.UUID.t(), String.t(), keyword()) :: :ok
  def mark_interrupted(session_id, reason, opts \\ [])
      when is_binary(session_id) and is_binary(reason) do
    terminal? = Keyword.get(opts, :terminal, false)
    next_state = if terminal?, do: "expired", else: "pending"
    now = Clock.utc_now()

    Delivery
    |> where(
      [d],
      d.agent_session_id == ^session_id and d.state in ["pending", "injected"]
    )
    |> Repo.update_all(
      set: [state: next_state, last_error: String.slice(reason, 0, 1_000), updated_at: now],
      inc: [attempt_count: 1]
    )

    :ok
  end
end
