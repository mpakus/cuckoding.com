defmodule CuckodingShellSpike.Router do
  use Phoenix.Router
  import Phoenix.LiveView.Router

  pipeline :browser do
    plug(:accepts, ["html"])
    plug(:fetch_session)
    plug(:put_secure_browser_headers)
  end

  pipeline :shell do
    plug(:accepts, ["json"])
  end

  scope "/" do
    pipe_through(:browser)
    get("/open", CuckodingShellSpike.ShellController, :open)
    get("/unauthorized", CuckodingShellSpike.ShellController, :unauthorized)

    live_session :browser, on_mount: [{CuckodingShellSpike.AuthHook, :browser}] do
      live("/", CuckodingShellSpike.DashboardLive, :index)
      live("/settings", CuckodingShellSpike.DashboardLive, :settings)
    end
  end

  scope "/shell" do
    pipe_through(:shell)
    post("/bootstrap", CuckodingShellSpike.ShellController, :bootstrap)
    post("/tokens", CuckodingShellSpike.ShellController, :token)
    get("/status", CuckodingShellSpike.ShellController, :status)
    post("/shutdown", CuckodingShellSpike.ShellController, :shutdown)
    post("/crash", CuckodingShellSpike.ShellController, :crash)
  end
end
