defmodule Cuckoding.DataCase do
  @moduledoc false
  use ExUnit.CaseTemplate

  alias Ecto.Adapters.SQL.Sandbox
  alias ExUnit.Callbacks

  using do
    quote do
      import Ecto.Query
      alias Cuckoding.Repo
    end
  end

  setup tags do
    setup_sandbox(tags)
    :ok
  end

  def setup_sandbox(tags) do
    owner = Sandbox.start_owner!(Cuckoding.Repo, shared: not tags[:async])
    Callbacks.on_exit(fn -> Sandbox.stop_owner(owner) end)
  end
end
