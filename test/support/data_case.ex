defmodule AgentDesk.DataCase do
  @moduledoc """
  This module defines the setup for tests requiring
  access to the application's data layer.

  You may define functions here to be used as helpers in
  your tests.

  Finally, if the test case interacts with the database,
  we enable the SQL sandbox, so changes done to the database
  are reverted at the end of every test. If you are using
  PostgreSQL, you can even run database tests asynchronously
  by setting `use AgentDesk.DataCase, async: true`, although
  this option is not recommended for other databases.
  """

  use ExUnit.CaseTemplate

  alias Ecto.Adapters.SQL.Sandbox

  using do
    quote do
      alias AgentDesk.Repo

      import Ecto
      import Ecto.Changeset
      import Ecto.Query
      import AgentDesk.DataCase
    end
  end

  setup tags do
    AgentDesk.DataCase.setup_sandbox(tags)
    on_exit(&AgentDesk.DataCase.stop_project_runtimes/0)
    :ok
  end

  @doc false
  def stop_project_runtimes do
    AgentDesk.Projects.Supervisor
    |> DynamicSupervisor.which_children()
    |> Enum.each(&stop_child/1)

    AgentDesk.ProviderProcessSupervisor
    |> DynamicSupervisor.which_children()
    |> Enum.each(&stop_child/1)
  end

  defp stop_child({_id, pid, _type, _modules}) when is_pid(pid) do
    if Process.alive?(pid), do: GenServer.stop(pid, :shutdown, 1_000)
  end

  defp stop_child(_other), do: :ok

  @doc """
  Sets up the sandbox based on the test tags.
  """
  def setup_sandbox(tags) do
    pid = Sandbox.start_owner!(AgentDesk.Repo, shared: not tags[:async])
    on_exit(fn -> Sandbox.stop_owner(pid) end)
  end

  @doc """
  A helper that transforms changeset errors into a map of messages.

      assert {:error, changeset} = Accounts.create_user(%{password: "short"})
      assert "password is too short" in errors_on(changeset).password
      assert %{password: ["password is too short"]} = errors_on(changeset)

  """
  def wait_until(fun, attempts \\ 80) do
    cond do
      attempts <= 0 ->
        false

      value = fun.() ->
        value

      true ->
        receive do
        after
          50 -> wait_until(fun, attempts - 1)
        end
    end
  end

  def errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
