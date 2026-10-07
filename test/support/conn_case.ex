defmodule CuckodingWeb.ConnCase do
  @moduledoc false
  use ExUnit.CaseTemplate

  using do
    quote do
      @endpoint CuckodingWeb.Endpoint
      use CuckodingWeb, :verified_routes
      import Plug.Conn
      import Phoenix.ConnTest
      import CuckodingWeb.ConnCase
    end
  end

  setup tags do
    Cuckoding.DataCase.setup_sandbox(tags)
    {:ok, conn: local_conn()}
  end

  def local_conn do
    Phoenix.ConnTest.build_conn() |> Map.put(:host, "127.0.0.1") |> Map.put(:port, 4002)
  end

  def sign_in(conn) do
    {:ok, session} = Cuckoding.ShellAuth.exchange(Cuckoding.ShellAuth.handoff())

    Plug.Test.init_test_session(conn, %{
      "session_id" => session.token,
      "expires_at" => session.expires_at
    })
  end
end
