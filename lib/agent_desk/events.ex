defmodule AgentDesk.Events do
  @moduledoc """
  Append-only event writer.

  Persist the event in the same transaction as the state change when recovery
  depends on it. PubSub notification happens after commit.
  """

  import Ecto.Query

  alias AgentDesk.Clock
  alias AgentDesk.Events.Event
  alias AgentDesk.Ids
  alias AgentDesk.Repo

  @spec append(map()) :: {:ok, Event.t()} | {:error, Ecto.Changeset.t()}
  def append(attrs) when is_map(attrs), do: append(Repo, attrs)

  @spec append(module(), map()) :: {:ok, Event.t()} | {:error, Ecto.Changeset.t()}
  def append(repo, attrs) when is_map(attrs) do
    attrs =
      attrs
      |> stringify_keys()
      |> Map.put_new("id", Ids.generate())
      |> Map.put_new("occurred_at", Clock.utc_now())
      |> Map.put_new("payload", %{})
      |> Map.put_new("correlation_id", Ids.generate())

    %Event{}
    |> Event.changeset(attrs)
    |> repo.insert()
  end

  @spec list_for_project(Ecto.UUID.t(), keyword()) :: [Event.t()]
  def list_for_project(project_id, opts \\ []) when is_binary(project_id) do
    limit = Keyword.get(opts, :limit, 50)

    Event
    |> where([e], e.project_id == ^project_id)
    |> order_by([e], desc: e.occurred_at)
    |> limit(^limit)
    |> Repo.all()
  end

  defp stringify_keys(attrs) do
    Map.new(attrs, fn
      {key, value} when is_atom(key) -> {Atom.to_string(key), value}
      {key, value} -> {key, value}
    end)
  end
end
