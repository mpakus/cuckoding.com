defmodule CuckodingWeb.ConnCase do
  @moduledoc false
  use ExUnit.CaseTemplate

  using do
    quote do
      @endpoint CuckodingWeb.Endpoint

      use CuckodingWeb, :verified_routes

      import Phoenix.ConnTest
      import Plug.Conn
    end
  end

  setup tags do
    Cuckoding.DataCase.setup_sandbox(tags)
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end
end
