defmodule CuckodingWeb.ShellControllerTest do
  use CuckodingWeb.ConnCase, async: false

  alias Cuckoding.Shell.Auth

  setup do
    path = bootstrap_file()
    start_supervised!({Auth, path})
    %{bootstrap: bootstrap_token()}
  end

  test "rejects unauthorized access and consumes browser tokens once", %{
    conn: conn,
    bootstrap: bootstrap
  } do
    assert conn |> loopback() |> get("/") |> redirected_to() == "/unauthorized"
    assert conn |> loopback() |> get("/shell/status") |> response(401) == "unauthorized"
    assert conn |> Map.put(:host, "example.com") |> get("/shell/status") |> response(403)

    assert conn
           |> loopback()
           |> put_req_header("origin", "https://example.com")
           |> get("/shell/status")
           |> response(403) == "forbidden"

    bootstrap_response =
      conn
      |> loopback()
      |> put_req_header("authorization", "Bearer #{bootstrap}")
      |> post("/shell/bootstrap")

    shell = json_response(bootstrap_response, 200)["shell_token"]

    assert conn
           |> loopback()
           |> put_req_header("authorization", "Bearer #{bootstrap}")
           |> post("/shell/bootstrap")
           |> response(401) == "unauthorized"

    token_response =
      conn
      |> loopback()
      |> put_req_header("authorization", "Bearer #{shell}")
      |> post("/shell/tokens")

    browser = json_response(token_response, 200)["token"]

    opened =
      conn
      |> loopback()
      |> get("/open?token=#{browser}&next=/settings/plugins")

    assert redirected_to(opened) == "/settings/plugins"
    assert get_session(opened, :browser_authenticated)

    assert conn
           |> loopback()
           |> get("/open?token=#{browser}")
           |> response(401) == "unauthorized"

    safe_token =
      conn
      |> loopback()
      |> put_req_header("authorization", "Bearer #{shell}")
      |> post("/shell/tokens")
      |> json_response(200)
      |> Map.fetch!("token")

    assert conn
           |> loopback()
           |> get("/open?token=#{safe_token}&next=https://example.com")
           |> redirected_to() == "/"
  end

  test "shutdown completes the run policy before stopping the runtime", %{
    conn: conn,
    bootstrap: bootstrap
  } do
    parent = self()
    previous_policy = Application.get_env(:cuckoding, :shell_quit_policy)
    previous_stop = Application.get_env(:cuckoding, :shell_stop_callback)

    Application.put_env(:cuckoding, :shell_quit_policy, fn ->
      send(parent, :policy_complete)
      :ok
    end)

    Application.put_env(:cuckoding, :shell_stop_callback, fn code ->
      send(parent, {:runtime_stopped, code})
    end)

    on_exit(fn ->
      restore_env(:shell_quit_policy, previous_policy)
      restore_env(:shell_stop_callback, previous_stop)
    end)

    shell = bootstrap_shell(conn, bootstrap)

    response =
      conn
      |> loopback()
      |> put_req_header("authorization", "Bearer #{shell}")
      |> post("/shell/shutdown")

    assert json_response(response, 200) == %{"status" => "stopping"}
    assert_received :policy_complete
    assert_receive {:runtime_stopped, 0}, 1_000
  end

  test "shutdown stays alive when the run policy cannot hibernate safely", %{
    conn: conn,
    bootstrap: bootstrap
  } do
    parent = self()
    previous_policy = Application.get_env(:cuckoding, :shell_quit_policy)
    previous_stop = Application.get_env(:cuckoding, :shell_stop_callback)

    Application.put_env(:cuckoding, :shell_quit_policy, fn -> {:error, :unsafe} end)
    Application.put_env(:cuckoding, :shell_stop_callback, fn _code -> send(parent, :stopped) end)

    on_exit(fn ->
      restore_env(:shell_quit_policy, previous_policy)
      restore_env(:shell_stop_callback, previous_stop)
    end)

    shell = bootstrap_shell(conn, bootstrap)

    response =
      conn
      |> loopback()
      |> put_req_header("authorization", "Bearer #{shell}")
      |> post("/shell/shutdown")

    assert json_response(response, 409) == %{"error" => "shutdown_blocked"}
    refute_receive :stopped, 150
  end

  defp bootstrap_shell(conn, bootstrap) do
    conn
    |> loopback()
    |> put_req_header("authorization", "Bearer #{bootstrap}")
    |> post("/shell/bootstrap")
    |> json_response(200)
    |> Map.fetch!("shell_token")
  end

  defp loopback(conn), do: %{conn | host: "127.0.0.1", port: 4002}

  defp bootstrap_file do
    directory =
      Path.join(System.tmp_dir!(), "cuckoding-shell-web-#{System.unique_integer([:positive])}")

    File.mkdir_p!(directory)
    on_exit(fn -> File.rm_rf!(directory) end)

    path = Path.join(directory, "bootstrap")
    File.write!(path, String.duplicate("s", 128) <> "\n" <> bootstrap_token(), [:exclusive])
    File.chmod!(path, 0o600)
    path
  end

  defp bootstrap_token, do: String.duplicate("b", 64)

  defp restore_env(key, nil), do: Application.delete_env(:cuckoding, key)
  defp restore_env(key, value), do: Application.put_env(:cuckoding, key, value)
end
