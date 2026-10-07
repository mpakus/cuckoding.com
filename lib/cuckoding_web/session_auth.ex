defmodule CuckodingWeb.SessionAuth do
  @moduledoc "Check DB authorization on mount, on every LiveView event and at expiry."
  import Phoenix.LiveView
  import Phoenix.Component, only: [assign: 3]

  def on_mount(:default, _params, session, socket) do
    if Cuckoding.ShellAuth.valid_session?(session["session_id"]) do
      if connected?(socket) do
        remaining = max(session["expires_at"] - System.system_time(:second), 0)
        Process.send_after(self(), :session_expired, remaining * 1_000)
      end

      socket =
        socket
        |> assign(:session_id, session["session_id"])
        |> attach_hook(:session_check, :handle_event, &authorize_event/3)
        |> attach_hook(:session_check, :handle_info, fn _, socket ->
          authorize_event(nil, nil, socket)
        end)

      {:cont, socket}
    else
      {:halt, redirect(socket, to: "/locked")}
    end
  end

  defp authorize_event(_, _, socket) do
    if Cuckoding.ShellAuth.valid_session?(socket.assigns.session_id),
      do: {:cont, socket},
      else: {:halt, redirect(socket, to: "/locked")}
  end
end
