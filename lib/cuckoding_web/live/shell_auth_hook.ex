defmodule CuckodingWeb.ShellAuthHook do
  @moduledoc false

  import Phoenix.LiveView

  def on_mount(:browser, _params, session, socket) do
    if not Cuckoding.Shell.Auth.required?() or session["browser_authenticated"] == true do
      {:cont, socket}
    else
      {:halt, redirect(socket, to: "/unauthorized")}
    end
  end
end
