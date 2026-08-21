defmodule AgentDesk.Storage do
  @moduledoc """
  Application-data paths for the local desktop runtime.

  Canonical SQLite, worktrees, transcripts, diagnostics, and XERJ data belong
  here rather than in the opened Git repository.
  """

  @spec data_root() :: String.t()
  def data_root do
    Application.get_env(:agent_desk, :data_root) || default_data_root()
  end

  @spec default_data_root() :: String.t()
  def default_data_root do
    case :os.type() do
      {:unix, :darwin} ->
        Path.join([System.user_home!(), "Library", "Application Support", "AgentDesk"])

      {:win32, _} ->
        Path.join([System.get_env("APPDATA") || System.user_home!(), "AgentDesk"])

      {:unix, _} ->
        xdg = System.get_env("XDG_DATA_HOME") || Path.join(System.user_home!(), ".local/share")
        Path.join(xdg, "agentdesk")
    end
  end

  @spec ensure_data_root!() :: String.t()
  def ensure_data_root! do
    root = data_root()
    File.mkdir_p!(root)
    root
  end

  @spec project_dir(Ecto.UUID.t()) :: String.t()
  def project_dir(project_id) when is_binary(project_id) do
    Path.join([data_root(), "projects", project_id])
  end

  @spec session_dir(Ecto.UUID.t(), Ecto.UUID.t()) :: String.t()
  def session_dir(project_id, session_id)
      when is_binary(project_id) and is_binary(session_id) do
    Path.join([project_dir(project_id), "sessions", session_id])
  end
end
