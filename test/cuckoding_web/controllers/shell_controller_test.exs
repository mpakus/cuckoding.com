defmodule CuckodingWeb.ShellControllerTest do
  use CuckodingWeb.ConnCase
  alias Cuckoding.{Event, Repo, ShellAuth}

  setup do
    bootstrap = ShellAuth.token()
    Supervisor.terminate_child(Cuckoding.Supervisor, ShellAuth)
    Application.put_env(:cuckoding, :bootstrap_hash, ShellAuth.digest(bootstrap))
    {:ok, _} = Supervisor.restart_child(Cuckoding.Supervisor, ShellAuth)
    {:ok, shell} = ShellAuth.bootstrap(bootstrap)
    %{shell: shell}
  end

  test "heartbeat returns only a bounded decision and accepts authenticated native observations",
       %{conn: conn, shell: shell} do
    response =
      conn
      |> put_req_header("authorization", "Bearer " <> shell)
      |> put_req_header("x-cc-power-state", "released")
      |> post("/shell/status")
      |> json_response(200)

    assert response == %{
             "status" => "ready",
             "version" => "0.1.0",
             "idle_sleep" => %{
               "contract" => "shell-lease-v1",
               "requested" => false,
               "lease_seconds" => 15
             }
           }

    assert ShellAuth.power_status().state == "released"

    # The isolated source UI launcher does not own a native assertion.
    assert conn
           |> put_req_header("authorization", "Bearer " <> shell)
           |> post("/shell/status")
           |> json_response(200) == response

    assert Repo.aggregate(Event, :count) == 2

    assert conn
           |> put_req_header("authorization", "Bearer " <> shell)
           |> put_req_header("x-cc-power-state", "released")
           |> post("/shell/quit")
           |> response(202)
  end

  test "browser authority, foreign callers and invalid report values cannot report power", %{
    conn: conn,
    shell: shell
  } do
    assert conn
           |> sign_in()
           |> put_req_header("x-cc-power-state", "held")
           |> post("/shell/status")
           |> response(401)

    assert conn
           |> put_req_header("authorization", "Bearer wrong")
           |> put_req_header("x-cc-power-state", "held")
           |> post("/shell/status")
           |> response(401)

    assert conn
           |> put_req_header("authorization", "Bearer " <> shell)
           |> put_req_header("x-cc-power-state", "held, raw-error")
           |> post("/shell/status")
           |> response(400)

    assert conn
           |> put_req_header("authorization", "Bearer " <> shell)
           |> put_req_header("origin", "https://evil.test")
           |> put_req_header("x-cc-power-state", "held")
           |> post("/shell/status")
           |> response(403)

    assert ShellAuth.power_status().state == "unknown"
  end
end
