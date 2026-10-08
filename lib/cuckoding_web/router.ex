defmodule CuckodingWeb.Router do
  use CuckodingWeb, :router

  # Boundary sets the stricter CSP, including the actual ephemeral WebSocket port.
  # sobelow_skip ["Config.CSP"]
  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {CuckodingWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  scope "/", CuckodingWeb do
    post "/shell/bootstrap", ShellController, :bootstrap, log: false
    post "/shell/open", ShellController, :open, log: false
    post "/shell/status", ShellController, :status, log: false
    post "/shell/quit", ShellController, :quit, log: false
  end

  scope "/", CuckodingWeb do
    pipe_through :browser
    get "/open", SessionController, :open, log: false
    get "/locked", SessionController, :locked, log: false
    get "/codex/login/:id", SessionController, :codex_login, log: false
    get "/specifications/:id/download", SessionController, :specification, log: false

    live_session :authenticated, on_mount: CuckodingWeb.SessionAuth do
      live "/", HomeLive, :home
      live "/settings", HomeLive, :settings
      live "/team", TeamLive, :team
      live "/arenas", ArenaLive, :arenas
      live "/arenas/:arena_id", TabulaLive, :index
      live "/arenas/:arena_id/checks", ProjectChecksLive, :checks
      live "/arenas/:arena_id/tabulae/:id", TabulaLive, :show
      live "/about", HomeLive, :about
    end
  end
end
