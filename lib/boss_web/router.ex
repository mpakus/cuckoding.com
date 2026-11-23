defmodule BossWeb.Router do
  use BossWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {BossWeb.Layouts, :root}
    plug :protect_from_forgery

    plug :put_secure_browser_headers, %{
      "referrer-policy" => "same-origin",
      "content-security-policy" =>
        "default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; connect-src 'self' ws://127.0.0.1:* ws://localhost:*; frame-ancestors 'none'; base-uri 'self'; form-action 'self'"
    }
  end

  scope "/", BossWeb do
    pipe_through :browser

    live_session :local do
      live "/", HomeLive
      live "/agents", AgentsLive
      live "/projects/:id", ProjectLive
      live "/projects/:id/tasks/:task_id", ProjectLive
    end
  end
end
