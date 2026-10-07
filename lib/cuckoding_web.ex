defmodule CuckodingWeb do
  @moduledoc false
  def static_paths, do: ~w(assets favicon.svg)

  def router do
    quote do
      use Phoenix.Router, helpers: false
      import Plug.Conn
      import Phoenix.Controller
      import Phoenix.LiveView.Router
    end
  end

  def controller do
    quote do
      use Phoenix.Controller, formats: [:html, :json]
      import Plug.Conn
      unquote(verified_routes())
    end
  end

  def html do
    quote do
      use Phoenix.Component
      import Phoenix.Controller, only: [get_csrf_token: 0]
      unquote(verified_routes())
    end
  end

  def live_view do
    quote do
      use Phoenix.LiveView
      unquote(verified_routes())
    end
  end

  def verified_routes do
    quote do
      use Phoenix.VerifiedRoutes,
        endpoint: CuckodingWeb.Endpoint,
        router: CuckodingWeb.Router,
        statics: CuckodingWeb.static_paths()
    end
  end

  defmacro __using__(which), do: apply(__MODULE__, which, [])
end
