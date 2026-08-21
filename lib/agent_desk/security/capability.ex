defmodule AgentDesk.Security.Capability do
  @moduledoc """
  Short-lived per-session Agent Hub tokens. SQLite stores only the hash.
  """

  alias AgentDesk.Agents
  alias AgentDesk.Agents.Session
  alias AgentDesk.Clock
  alias AgentDesk.Ids
  alias AgentDesk.Repo

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
      %Session{} = session -> check_expiry(session)
      nil -> {:error, :unauthorized}
    end
  end

  def authenticate(_), do: {:error, :unauthorized}

  defp check_expiry(%Session{capability_expires_at: nil} = session), do: {:ok, session}

  defp check_expiry(%Session{} = session) do
    case DateTime.compare(Clock.utc_now(), session.capability_expires_at) do
      :gt -> {:error, :expired}
      _ -> {:ok, session}
    end
  end
end
