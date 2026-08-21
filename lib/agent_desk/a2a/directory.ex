defmodule AgentDesk.A2A.Directory do
  @moduledoc """
  Capability-safe peer discovery. Never returns credentials or private prompts.
  """

  import Ecto.Query

  alias AgentDesk.A2A.AgentCard
  alias AgentDesk.Repo
  alias AgentDesk.Scope

  @spec list_agents(Scope.t()) :: [map()]
  def list_agents(%Scope{project: project}) do
    AgentCard
    |> where([c], c.project_id == ^project.id)
    |> order_by([c], asc: c.name)
    |> Repo.all()
    |> Enum.map(&public_card/1)
  end

  @spec get_agent(Scope.t(), Ecto.UUID.t()) :: {:ok, map()} | {:error, :not_found}
  def get_agent(%Scope{project: project}, agent_id) do
    case Repo.get_by(AgentCard, project_id: project.id, agent_session_id: agent_id) do
      %AgentCard{} = card -> {:ok, public_card(card)}
      nil -> {:error, :not_found}
    end
  end

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
