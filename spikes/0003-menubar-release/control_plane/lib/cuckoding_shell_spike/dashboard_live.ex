defmodule CuckodingShellSpike.DashboardLive do
  use Phoenix.LiveView

  @impl true
  def mount(_params, _session, socket), do: {:ok, assign(socket, :page_title, "Cuckoding")}

  @impl true
  def render(assigns) do
    ~H"""
    <!doctype html>
    <html lang="en">
      <head><meta charset="utf-8" /><title>{@page_title}</title></head>
      <body><main><h1>{@page_title}</h1><p>Authenticated LiveView shell spike.</p></main></body>
    </html>
    """
  end
end
