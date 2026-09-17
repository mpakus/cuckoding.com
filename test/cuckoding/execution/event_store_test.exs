defmodule Cuckoding.Execution.EventStoreTest do
  use Cuckoding.DataCase, async: false

  alias Cuckoding.Execution.Command
  alias Cuckoding.Execution.EventStore
  alias Cuckoding.Execution.RunEvent

  test "commits a projection and its event atomically" do
    run_id = Ecto.UUID.generate()
    key = Ecto.UUID.generate()

    projection = fn repo, sequence ->
      attrs = command_attrs(key, %{"sequence" => sequence})
      {:ok, repo.insert!(Command.create_changeset(%Command{}, attrs))}
    end

    assert {:ok, {%RunEvent{sequence: 1}, %Command{id: command_id}}} =
             EventStore.append(run_id, event_attrs(), projection)

    assert Repo.get!(Command, command_id).payload == %{"sequence" => 1}
  end

  test "rolls the projection back when the event is invalid" do
    key = Ecto.UUID.generate()

    projection = fn repo, _sequence ->
      command = repo.insert!(Command.create_changeset(%Command{}, command_attrs(key)))
      {:ok, command.id}
    end

    assert {:error, %Ecto.Changeset{}} =
             EventStore.append(
               Ecto.UUID.generate(),
               Map.delete(event_attrs(), :public_summary),
               projection
             )

    refute Repo.get_by(Command, idempotency_key: key)
  end

  test "database triggers reject event updates and deletes" do
    assert {:ok, {event, nil}} = EventStore.append(Ecto.UUID.generate(), event_attrs())

    assert_raise Exqlite.Error, ~r/append-only/, fn ->
      Repo.update_all(from(item in RunEvent, where: item.id == ^event.id),
        set: [public_summary: "changed"]
      )
    end

    assert_raise Exqlite.Error, ~r/append-only/, fn ->
      Repo.delete_all(from(item in RunEvent, where: item.id == ^event.id))
    end
  end

  defp event_attrs do
    %{
      event_type: "run.started",
      public_summary: "Run started",
      payload: %{"source" => "test"}
    }
  end

  defp command_attrs(key, payload \\ %{}) do
    %{
      idempotency_key: key,
      kind: "test.projection",
      target_type: "run",
      target_id: Ecto.UUID.generate(),
      payload: payload,
      not_before: Cuckoding.Clock.wall_now()
    }
  end
end
