defmodule AgentDesk.Agents do
  @moduledoc """
  Provider sessions owned by a project.
  """

  alias AgentDesk.Agents.Session
  alias AgentDesk.Clock
  alias AgentDesk.Ids
  alias AgentDesk.Repo
  alias AgentDesk.Scope

  @spec create_session(Scope.t(), map()) :: {:ok, Session.t()} | {:error, Ecto.Changeset.t()}
  def create_session(%Scope{project: project}, attrs) when is_map(attrs) do
    now = Clock.utc_now()

    attrs =
      attrs
      |> Map.put(:project_id, project.id)
      |> Map.put_new(:status, "idle")
      |> Map.put_new(:started_at, now)
      |> Map.put_new(:capability_hash, capability_hash())
      |> Map.put_new(:id, Ids.generate())

    %Session{}
    |> Session.changeset(attrs)
    |> Repo.insert()
  end

  @spec get_session(Scope.t(), Ecto.UUID.t()) :: {:ok, Session.t()} | {:error, :not_found}
  def get_session(%Scope{project: project}, id) when is_binary(id) do
    case Repo.get_by(Session, id: id, project_id: project.id) do
      %Session{} = session -> {:ok, session}
      nil -> {:error, :not_found}
    end
  end

  defp capability_hash do
    :sha256
    |> :crypto.hash(:crypto.strong_rand_bytes(32))
    |> Base.encode16(case: :lower)
  end
end
