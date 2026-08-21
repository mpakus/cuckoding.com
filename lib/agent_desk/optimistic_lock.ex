defmodule AgentDesk.OptimisticLock do
  @moduledoc """
  Optimistic version checks for task and delegation transitions.
  """

  import Ecto.Changeset

  @spec check(Ecto.Changeset.t(), integer()) :: Ecto.Changeset.t()
  def check(%Ecto.Changeset{} = changeset, expected) when is_integer(expected) do
    current = changeset.data.lock_version

    if current == expected do
      optimistic_lock(changeset, :lock_version)
    else
      add_error(changeset, :lock_version, "stale version")
    end
  end
end
