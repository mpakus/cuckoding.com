defmodule AgentDesk.Agents do
  @moduledoc """
  Provider sessions owned by a project.
  """

  import Ecto.Query

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

  @spec list_sessions(Scope.t() | Ecto.UUID.t()) :: [Session.t()]
  def list_sessions(%Scope{project: project}), do: list_sessions(project.id)

  def list_sessions(project_id) when is_binary(project_id) do
    Session
    |> where([s], s.project_id == ^project_id)
    |> order_by([s], asc: s.inserted_at)
    |> Repo.all()
  end

  @spec visible_sessions(Scope.t()) :: [Session.t()]
  def visible_sessions(%Scope{} = scope) do
    Enum.filter(list_sessions(scope), fn session ->
      Map.get(session.settings || %{}, "tab_open", true) != false
    end)
  end

  @spec update_session(Session.t(), map()) :: {:ok, Session.t()} | {:error, Ecto.Changeset.t()}
  def update_session(%Session{} = session, attrs) when is_map(attrs) do
    session
    |> Session.changeset(attrs)
    |> Repo.update()
  end

  @spec hide_tab(Session.t()) :: {:ok, Session.t()} | {:error, Ecto.Changeset.t()}
  def hide_tab(%Session{} = session) do
    settings = Map.put(session.settings || %{}, "tab_open", false)
    update_session(session, %{settings: settings})
  end

  @spec interrupt_orphans(Ecto.UUID.t()) :: :ok
  def interrupt_orphans(project_id) when is_binary(project_id) do
    now = Clock.utc_now()

    Session
    |> where(
      [s],
      s.project_id == ^project_id and
        s.status in ["queued", "starting", "idle", "working", "waiting", "blocked"]
    )
    |> Repo.update_all(set: [status: "interrupted", updated_at: now])

    :ok
  end

  defp capability_hash do
    :sha256
    |> :crypto.hash(:crypto.strong_rand_bytes(32))
    |> Base.encode16(case: :lower)
  end
end
