defmodule CuckodingShellSpike.AuthHook do
  import Phoenix.LiveView

  def on_mount(:browser, _params, %{"browser_authenticated" => true}, socket),
    do: {:cont, socket}

  def on_mount(:browser, _params, _session, socket),
    do: {:halt, redirect(socket, to: "/unauthorized")}
end
