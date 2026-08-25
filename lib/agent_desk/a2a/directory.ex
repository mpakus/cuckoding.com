defmodule AgentDesk.A2A.Directory do
  @moduledoc """
  Capability-safe peer discovery. Never returns credentials or private prompts.
  """

  import Ecto.Query

  alias AgentDesk.A2A.AgentCard
  alias AgentDesk.A2A.Authorization
  alias AgentDesk.Agents.Session
  alias AgentDesk.Repo
  alias AgentDesk.Scope

  @spec list_agents(Scope.t()) :: [map()]
  def list_agents(%Scope{project: project}) do
    AgentCard
    |> join(:inner, [card], session in Session, on: session.id == card.agent_session_id)
    |> where([card], card.project_id == ^project.id)
    |> order_by([c], asc: c.name)
    |> select([card, session], {card, session})
    |> Repo.all()
    |> Enum.filter(fn {_card, session} -> Authorization.eligible_session?(session) end)
    |> Enum.map(fn {card, _session} -> public_card(card) end)
  end

  @spec get_agent(Scope.t(), Ecto.UUID.t()) :: {:ok, map()} | {:error, :not_found}
  def get_agent(%Scope{project: project}, agent_id) when is_binary(agent_id) do
    with {:ok, _uuid} <- Ecto.UUID.cast(agent_id) do
      case Repo.one(
             from card in AgentCard,
               join: session in Session,
               on: session.id == card.agent_session_id,
               where: card.project_id == ^project.id and card.agent_session_id == ^agent_id,
               select: {card, session}
           ) do
        {%AgentCard{} = card, %Session{} = session} ->
          if Authorization.eligible_session?(session),
            do: {:ok, public_card(card)},
            else: {:error, :not_found}

        nil ->
          {:error, :not_found}
      end
    else
      :error -> {:error, :not_found}
    end
  end

  def get_agent(%Scope{}, _agent_id), do: {:error, :not_found}

  @spec find_agents(Scope.t(), keyword()) :: [map()]
  def find_agents(%Scope{} = scope, opts) do
    skill = opts[:skill]
    availability = opts[:availability]

    list_agents(scope)
    |> filter_skill(skill)
    |> filter_availability(availability)
  end

  defp public_card(%AgentCard{} = card) do
    %{
      agent_id: card.agent_session_id,
      name: card.name,
      description: card.description,
      revision: card.revision,
      skills: card.skills,
      input_modes: card.input_modes,
      output_modes: card.output_modes,
      features: card.features,
      availability: card.availability
    }
  end

  defp filter_skill(cards, nil), do: cards

  defp filter_skill(cards, skill) do
    Enum.filter(cards, fn card ->
      Enum.any?(card.skills, fn item ->
        to_string(item["id"] || item["name"] || "") == skill or
          skill in List.wrap(item["tags"])
      end)
    end)
  end

  defp filter_availability(cards, nil), do: cards

  defp filter_availability(cards, availability) do
    Enum.filter(cards, &(&1.availability == availability))
  end
end
