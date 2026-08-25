defmodule AgentDeskWeb.ControlAuthControllerTest do
  use AgentDeskWeb.ConnCase

  import Phoenix.LiveViewTest

  alias AgentDesk.Security.ControlAuth
  alias AgentDeskWeb.WorkspaceLive

  @moduletag control_auth: false

  test "rejects unsigned HTTP and LiveView access", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert response(conn, :unauthorized) == "Desktop control authorization required."

    assert {:error, {:redirect, %{to: "/control/unauthorized"}}} =
             live_isolated(build_conn(), WorkspaceLive, session: %{})
  end

  test "exchanges the configured bootstrap once for an authorized session", %{conn: conn} do
    token = String.duplicate("bootstrap-token-", 3)
    :ok = ControlAuth.reset_bootstrap_for_test(token)

    readiness = get(build_conn(), ~p"/control/readiness")
    assert response(readiness, :ok) == Base.encode16(:crypto.hash(:sha256, token), case: :lower)

    conn = get(conn, ~p"/control/bootstrap?token=#{token}")
    assert redirected_to(conn) == ~p"/"
    assert ControlAuth.authorized_session?(get_session(conn))

    second = get(build_conn(), ~p"/control/bootstrap?token=#{token}")
    assert response(second, :unauthorized) == "Desktop control authorization required."

    unavailable = get(build_conn(), ~p"/control/readiness")
    assert response(unavailable, :service_unavailable) == "unavailable"
  end
end
