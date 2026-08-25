defmodule AgentDeskWeb.Router do
  use AgentDeskWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {AgentDeskWeb.Layouts, :root}
    plug :protect_from_forgery

    plug :put_secure_browser_headers, %{
      "content-security-policy" =>
        "default-src 'self'; img-src 'self' data: asset: tauri:; style-src 'self' 'unsafe-inline'; " <>
          "script-src 'self' 'unsafe-eval' 'unsafe-inline'; " <>
          "connect-src 'self' ipc: tauri: http://ipc.localhost https://ipc.localhost " <>
          "ws://127.0.0.1:* ws://localhost:* http://127.0.0.1:* http://localhost:*; " <>
          "font-src 'self'; object-src 'none'; base-uri 'self'; form-action 'self'; frame-ancestors 'none'"
    }
  end

  pipeline :control_authorized do
    plug AgentDeskWeb.Plugs.RequireControlAuth
  end

  scope "/control", AgentDeskWeb do
    pipe_through :browser

    get "/readiness", ControlAuthController, :readiness
    get "/bootstrap", ControlAuthController, :bootstrap
    get "/unauthorized", ControlAuthController, :unauthorized
  end

  scope "/", AgentDeskWeb do
    pipe_through [:browser, :control_authorized]

    live "/", WorkspaceLive, :index
    live "/projects/:id", WorkspaceLive, :show
  end

  if Application.compile_env(:agent_desk, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through [:browser, :control_authorized]

      live_dashboard "/dashboard", metrics: AgentDeskWeb.Telemetry
    end
  end
end
