defmodule Cuckoding.Execution.Commands do
  @moduledoc """
  Inserts commands once by idempotency key and invokes dispatch only after commit.
  """

  alias Cuckoding.Execution.Command
  alias Cuckoding.Execution.CommandDispatcher
  alias Cuckoding.Repo

  def enqueue(attrs, options \\ []) when is_map(attrs) do
    now = Keyword.get(options, :now, Cuckoding.Clock.wall_now())

    attrs =
      attrs
      |> Map.put_new(:payload, %{})
      |> Map.put_new(:state, "pending")
      |> Map.put_new(:attempts, 0)
      |> Map.put_new(:max_attempts, 3)
      |> Map.put_new(:not_before, now)

    with {:ok, command} <- insert_or_fetch(attrs) do
      dispatch_after_commit(command, options)
    end
  end

  defp dispatch_after_commit(command, options) do
    callback =
      Keyword.get_lazy(options, :after_commit, fn ->
        fn committed -> CommandDispatcher.dispatch(committed.id, options) end
      end)

    case callback.(command) do
      {:ok, %Command{} = dispatched} -> {:ok, dispatched}
      :ok -> {:ok, Repo.get!(Command, command.id)}
      {:error, _reason} = error -> error
    end
  end

  defp insert_or_fetch(attrs) do
    Repo.transaction(fn ->
      changeset = Command.create_changeset(%Command{}, attrs)

      case Repo.insert(changeset) do
        {:ok, command} -> command
        {:error, failed} -> fetch_duplicate_or_rollback(failed, attrs)
      end
    end)
  end

  defp fetch_duplicate_or_rollback(changeset, attrs) do
    if Keyword.has_key?(changeset.errors, :idempotency_key) do
      Repo.get_by!(Command, idempotency_key: Map.fetch!(attrs, :idempotency_key))
    else
      Repo.rollback(changeset)
    end
  end
end
