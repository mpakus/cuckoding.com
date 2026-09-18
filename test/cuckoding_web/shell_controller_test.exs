defmodule CuckodingWeb.ShellControllerTest do
  use CuckodingWeb.ConnCase, async: false

  alias Cuckoding.Repo
  alias Cuckoding.Shell.Auth
  alias Cuckoding.Updates.Attempt

  setup do
    path = bootstrap_file()
    start_supervised!({Auth, path})

    update_root =
      Path.join(System.tmp_dir!(), "cuckoding-shell-update-#{System.unique_integer([:positive])}")

    previous_snapshot = Application.get_env(:cuckoding, :update_snapshot_options)
    previous_pending = Application.get_env(:cuckoding, :update_pending_path)

    Application.put_env(:cuckoding, :update_snapshot_options,
      backup_root: update_root,
      database_backup: &File.cp/2
    )

    Application.put_env(:cuckoding, :update_pending_path, Path.join(update_root, "pending.json"))

    on_exit(fn ->
      restore_env(:update_snapshot_options, previous_snapshot)
      restore_env(:update_pending_path, previous_pending)
      File.rm_rf!(update_root)
    end)

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

  test "update preparation snapshots state before install and health promotion", %{
    conn: conn,
    bootstrap: bootstrap
  } do
    shell = bootstrap_shell(conn, bootstrap)

    prepared =
      conn
      |> loopback()
      |> put_req_header("authorization", "Bearer #{shell}")
      |> post("/shell/update/prepare", %{version: "0.2.0", schema_change: true})
      |> json_response(200)

    attempt_id = prepared["attempt_id"]
    assert prepared["status"] == "prepared"
    assert Repo.get!(Attempt, attempt_id).backup_manifest_hash

    assert %{"status" => "installing"} =
             conn
             |> loopback()
             |> put_req_header("authorization", "Bearer #{shell}")
             |> post("/shell/update/installing", %{attempt_id: attempt_id})
             |> json_response(200)

    assert %{"status" => "healthy"} =
             conn
             |> loopback()
             |> put_req_header("authorization", "Bearer #{shell}")
             |> post("/shell/update/healthy")
             |> json_response(200)
  end

  test "update failure is audited and clears the pending install", %{
    conn: conn,
    bootstrap: bootstrap
  } do
    shell = bootstrap_shell(conn, bootstrap)

    attempt_id =
      conn
      |> loopback()
      |> put_req_header("authorization", "Bearer #{shell}")
      |> post("/shell/update/prepare", %{version: "0.2.0", schema_change: false})
      |> json_response(200)
      |> Map.fetch!("attempt_id")

    assert %{"status" => "failed"} =
             conn
             |> loopback()
             |> put_req_header("authorization", "Bearer #{shell}")
             |> post("/shell/update/failed", %{
               attempt_id: attempt_id,
               reason: "application_backup_failed"
             })
             |> json_response(200)

    assert Repo.get!(Attempt, attempt_id).failure_reason == "application_backup_failed"
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
