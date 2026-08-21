defmodule AgentDesk.A2A.Messaging do
  @moduledoc false

  import Ecto.Query

  alias AgentDesk.A2A.Delivery
  alias AgentDesk.A2A.Idempotency
  alias AgentDesk.A2A.Message
  alias AgentDesk.A2A.Participant
  alias AgentDesk.A2A.Parts
  alias AgentDesk.Agents.Session
  alias AgentDesk.Correlation
  alias AgentDesk.Ids
  alias AgentDesk.Repo
  alias AgentDesk.Scope

  @spec send(Scope.t(), map()) :: {:ok, Message.t()} | {:error, term()}
  def send(%Scope{agent_session: %Session{}} = scope, attrs) do
    key = Map.fetch!(attrs, :idempotency_key)
    canonical = Map.take(attrs, [:recipient_agent_id, :scope, :body, :context_id, :task_id])

    case Idempotency.transact(scope, "send_message", key, canonical, fn ->
           do_send(scope, attrs, key)
         end) do
      {:ok, _kind, %{"id" => id}} -> {:ok, Repo.get!(Message, id)}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec inbox(Scope.t(), integer() | nil) :: [Delivery.t()]
  def inbox(%Scope{agent_session: %Session{id: id}}, cursor \\ 0) do
    Delivery
    |> where([d], d.agent_session_id == ^id and d.inbox_sequence > ^cursor)
    |> order_by([d], asc: d.inbox_sequence)
    |> preload(:message)
    |> Repo.all()
  end

  defp do_send(%Scope{project: project, agent_session: sender} = scope, attrs, key) do
    with {:ok, parts} <- Parts.validate(scope, parts_from(attrs)),
         {:ok, recipients} <- recipients(scope, attrs) do
      correlation =
        Correlation.new(context_id: Map.fetch!(attrs, :context_id), idempotency_key: key)

      body = Map.get(attrs, :body) || text_projection(parts)

      {:ok, message} =
        %Message{}
        |> Message.changeset(%{
          id: Ids.generate(),
          project_id: project.id,
          context_id: Map.fetch!(attrs, :context_id),
          task_id: Map.get(attrs, :task_id),
          sender_agent_id: sender.id,
          recipient_agent_id: Map.get(attrs, :recipient_agent_id),
          scope: Map.get(attrs, :scope, "direct"),
          kind: Map.get(attrs, :kind, "info"),
          body: body,
          parts: parts,
          idempotency_key: key,
          correlation_id: correlation.correlation_id,
          causation_id: Map.get(attrs, :causation_id) || correlation.causation_id,
          reply_to_message_id: Map.get(attrs, :reply_to_message_id)
        })
        |> Repo.insert()

      Enum.each(recipients, &insert_delivery!(message.id, &1))
      {:ok, %{"id" => message.id}}
    end
  end

  defp recipients(%Scope{project: project, agent_session: sender}, attrs) do
    case Map.get(attrs, :scope, "direct") do
      "direct" ->
        {:ok, [Map.fetch!(attrs, :recipient_agent_id)]}

      "project" ->
        {:ok, other_sessions(project.id, sender.id)}

      "context" ->
        {:ok, context_members(Map.fetch!(attrs, :context_id)) -- [sender.id]}

      "task" ->
        task_id = Map.fetch!(attrs, :task_id)
        {:ok, Enum.filter(other_sessions(project.id, sender.id), &task_member?(task_id, &1))}

      _other ->
        {:error, :invalid_scope}
    end
  end

  defp other_sessions(project_id, sender_id) do
    Session
    |> where(
      [s],
      s.project_id == ^project_id and s.id != ^sender_id and
        s.status not in ["terminated", "terminating"]
    )
    |> select([s], s.id)
    |> Repo.all()
  end

  defp context_members(context_id) do
    Participant
    |> where([p], p.context_id == ^context_id)
    |> select([p], p.agent_session_id)
    |> Repo.all()
  end

  defp task_member?(task_id, session_id) do
    case Repo.get(AgentDesk.A2A.Task, task_id) do
      %{assigned_agent_id: ^session_id} -> true
      %{context_id: context_id} -> session_id in context_members(context_id)
      _ -> false
    end
  end

  defp insert_delivery!(message_id, agent_session_id) do
    sequence = next_inbox_sequence(agent_session_id)

    %Delivery{}
    |> Delivery.changeset(%{
      id: Ids.generate(),
      message_id: message_id,
      agent_session_id: agent_session_id,
      inbox_sequence: sequence,
      state: "pending"
    })
    |> Repo.insert!()
  end

  defp next_inbox_sequence(agent_session_id) do
    query =
      from d in Delivery,
        where: d.agent_session_id == ^agent_session_id,
        select: max(d.inbox_sequence)

    (Repo.one(query) || 0) + 1
  end

  defp parts_from(attrs) do
    Map.get(attrs, :parts) ||
      [%{"type" => "text", "text" => Map.get(attrs, :body, "")}]
  end

  defp text_projection(parts) do
    parts
    |> Enum.map_join("\n", fn
      %{"text" => text} -> text
      _ -> ""
    end)
    |> String.slice(0, 10_000)
  end
end
