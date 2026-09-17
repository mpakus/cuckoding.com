defmodule CuckodingWeb do
  @moduledoc """
  Shared Phoenix definitions for the local web control plane.
  """

  def static_paths, do: ~w(assets favicon.ico robots.txt)

  def router do
    quote do
      use Phoenix.Router, helpers: false

      import Phoenix.Controller
      import Phoenix.LiveView.Router
      import Plug.Conn
    end
  end

  def controller do
    quote do
      use Phoenix.Controller, formats: [:html, :json]

      import Plug.Conn
      unquote(verified_routes())
    end
  end

  def live_view do
    quote do
      use Phoenix.LiveView

      unquote(html_helpers())
    end
  end

  def html do
    quote do
      use Phoenix.Component

      import Phoenix.Controller, only: [get_csrf_token: 0]
      unquote(html_helpers())
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

  defp html_helpers do
    quote do
      import Phoenix.HTML
      alias CuckodingWeb.Layouts
      unquote(verified_routes())
    end
  end

  defmacro __using__(which) when is_atom(which), do: apply(__MODULE__, which, [])
end
