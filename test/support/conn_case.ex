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

  setup _tags do
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end
end
