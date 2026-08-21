defmodule AgentDesk.A2A.AgentCard do
  @moduledoc """
  Project-scoped safe capability card. Never stores secrets or hidden prompts.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias AgentDesk.Agents.Session
  alias AgentDesk.Projects.Project

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @type t :: %__MODULE__{}

  @availabilities ~w(offline starting idle busy blocked draining)
  @forbidden_skill_keys ~w(password token secret credential api_key)

  schema "agent_cards" do
    field :revision, :integer, default: 1
    field :name, :string
    field :description, :string
    field :skills, {:array, :map}, default: []
    field :input_modes, {:array, :string}, default: []
    field :output_modes, {:array, :string}, default: []
    field :features, :map, default: %{}
    field :availability, :string, default: "starting"
    field :published_at, :utc_datetime_usec

    belongs_to :project, Project
    belongs_to :agent_session, Session

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(card, attrs) do
    card
    |> cast(attrs, [
      :id,
      :project_id,
      :agent_session_id,
      :revision,
      :name,
      :description,
      :skills,
      :input_modes,
      :output_modes,
      :features,
      :availability,
      :published_at
    ])
    |> validate_required([
      :project_id,
      :agent_session_id,
      :revision,
      :name,
      :description,
      :availability,
      :published_at
    ])
    |> validate_inclusion(:availability, @availabilities)
    |> validate_number(:revision, greater_than: 0)
    |> validate_length(:name, max: 120)
    |> validate_length(:description, max: 2000)
    |> validate_safe_skills()
    |> unique_constraint(:agent_session_id)
    |> foreign_key_constraint(:project_id)
    |> foreign_key_constraint(:agent_session_id)
  end

  defp validate_safe_skills(changeset) do
    validate_change(changeset, :skills, fn :skills, skills ->
      cond do
        not is_list(skills) ->
          [skills: "must be a list"]

        length(skills) > 32 ->
          [skills: "too many skills"]

        Enum.any?(skills, &forbidden_skill?/1) ->
          [skills: "must not include credentials or hidden prompts"]

        true ->
          []
      end
    end)
  end

  defp forbidden_skill?(skill) when is_map(skill) do
    skill
    |> Map.keys()
    |> Enum.map(&to_string/1)
    |> Enum.any?(&(&1 in @forbidden_skill_keys))
  end

  defp forbidden_skill?(_), do: true
end
