defmodule CuckodingWeb.HealthControllerTest do
  use CuckodingWeb.ConnCase, async: true

  test "GET /health returns separated application and dependency status", %{conn: conn} do
    conn = get(conn, ~p"/health")

    assert %{
             "status" => "ok",
             "application" => %{"status" => "ok"},
             "dependencies" => %{"pubsub" => "ok", "web_endpoint" => "ok"}
           } = json_response(conn, 200)

    assert [request_id] = get_resp_header(conn, "x-request-id")
    assert get_resp_header(conn, "x-correlation-id") == [request_id]
  end

  test "GET /status returns redacted, allowlisted diagnostics", %{conn: conn} do
    conn = get(conn, ~p"/status")
    response = json_response(conn, 200)

    assert response["configuration"]["endpoint"]["bind"] == "127.0.0.1"
    refute inspect(response) =~ "secret_key_base"
  end
end
