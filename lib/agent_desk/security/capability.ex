defmodule AgentDesk.Security.Capability do
  @moduledoc """
  Short-lived per-session Agent Hub tokens. SQLite stores only the hash.
  """

  alias AgentDesk.Agents
  alias AgentDesk.Agents.Session
  alias AgentDesk.Clock
  alias AgentDesk.Ids
  alias AgentDesk.Repo

  import Ecto.Query

  @active_session_statuses ~w(queued starting idle working waiting blocked)

  @spec hash(String.t()) :: String.t()
  def hash(token) when is_binary(token) do
    :sha256 |> :crypto.hash(token) |> Base.encode16(case: :lower)
  end

  @spec issue(Session.t()) :: {:ok, String.t(), Session.t()} | {:error, term()}
  def issue(%Session{} = session) do
    token = Ids.generate() <> Ids.generate()
    expires = DateTime.add(Clock.utc_now(), 43_200, :second)

    case Agents.update_session(session, %{
           capability_hash: hash(token),
           capability_expires_at: expires
         }) do
      {:ok, updated} -> {:ok, token, updated}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec authenticate(String.t()) :: {:ok, Session.t()} | {:error, :unauthorized | :expired}
  def authenticate(token) when is_binary(token) do
    case Repo.get_by(Session, capability_hash: hash(token)) do
      %Session{} = session -> authorize_session(session)
      nil -> {:error, :unauthorized}
    end
  end

  def authenticate(_), do: {:error, :unauthorized}

  @spec rotate(Session.t()) :: {:ok, String.t(), Session.t()} | {:error, term()}
  def rotate(%Session{} = session), do: issue(session)

  @spec revoke(Session.t()) :: {:ok, Session.t()} | {:error, term()}
  def revoke(%Session{} = session) do
    Agents.update_session(session, %{
      capability_hash: hash(Ids.generate()),
      capability_expires_at: Clock.utc_now()
    })
  end

  @spec expire_due(Ecto.UUID.t()) :: :ok
  def expire_due(project_id) when is_binary(project_id) do
    now = Clock.utc_now()

    from(s in Session,
      where:
        s.project_id == ^project_id and not is_nil(s.capability_expires_at) and
          s.capability_expires_at <= ^now
    )
    |> Repo.update_all(set: [capability_hash: nil, updated_at: now])

    :ok
  end

  @spec revoke_project(Ecto.UUID.t(), keyword()) :: :ok
  def revoke_project(project_id, opts \\ []) when is_binary(project_id) do
    except = Keyword.get(opts, :except, [])
    now = Clock.utc_now()

    query =
      from(s in Session,
        where: s.project_id == ^project_id and not is_nil(s.capability_hash)
      )

    query =
      case except do
        [] -> query
        ids -> from(s in query, where: s.id not in ^ids)
      end

    Repo.update_all(query,
      set: [capability_hash: nil, capability_expires_at: now, updated_at: now]
    )

    :ok
  end

  defp authorize_session(%Session{status: status} = session)
       when status in @active_session_statuses do
    check_expiry(session)
  end

  defp authorize_session(%Session{}), do: {:error, :unauthorized}

  defp check_expiry(%Session{capability_expires_at: nil}), do: {:error, :unauthorized}

  defp check_expiry(%Session{} = session) do
    case DateTime.compare(Clock.utc_now(), session.capability_expires_at) do
      :lt -> {:ok, session}
      _ -> {:error, :expired}
    end
  end
end
