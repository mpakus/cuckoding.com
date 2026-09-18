defmodule CuckodingWeb.Router do
  use CuckodingWeb, :router

  @content_security_policy Enum.join(
                             [
                               "default-src 'self'",
                               "base-uri 'none'",
                               "connect-src 'self' ws://127.0.0.1:*",
                               "form-action 'self'",
                               "frame-ancestors 'none'",
                               "img-src 'self' data:",
                               "object-src 'none'",
                               "script-src 'self'",
                               "style-src 'self'"
                             ],
                             "; "
                           )

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {CuckodingWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers, %{"content-security-policy" => @content_security_policy}
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", CuckodingWeb do
    pipe_through :browser

    get "/open", ShellController, :open
    get "/unauthorized", ShellController, :unauthorized

    live_session :browser, on_mount: [{CuckodingWeb.ShellAuthHook, :browser}] do
      live "/", StatusLive, :index
      live "/agents", AgentFloorLive, :index
      live "/agents/:id", AgentLive, :show
      live "/knowledge", KnowledgeReviewLive, :index
      live "/knowledge/growth", KnowledgeGrowthLive, :index
      live "/knowledge/lineage", KnowledgeLineageLive, :index
      live "/settings/plugins", PluginSettingsLive, :index
      live "/runs/:id", RunLive, :show
      live "/boards/:id", BoardLive, :show
      live "/boards/:board_id/tasks/:id", TaskLive, :show
    end
  end

  scope "/", CuckodingWeb do
    pipe_through :api
    get "/health", HealthController, :health
    get "/status", HealthController, :status
    post "/api/knowledge/retrieve", KnowledgeRetrievalController, :create
  end

  scope "/shell", CuckodingWeb do
    pipe_through :api

    post "/bootstrap", ShellController, :bootstrap
    post "/tokens", ShellController, :token
    get "/status", ShellController, :status
    post "/shutdown", ShellController, :shutdown
  end
end
