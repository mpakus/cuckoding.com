defmodule Cuckoding.Foundation do
  @moduledoc "Idempotent setup commands and their committed public event stream."
  import Ecto.Query
  alias Cuckoding.{Command, Event, Repo, Workspace}

  def workspace, do: Repo.get!(Workspace, 1)
  def events, do: Repo.all(from e in Event, order_by: [desc: e.id], limit: 10)
  def pending?, do: Repo.exists?(from c in Command, where: c.state in ["pending", "running"])

  def discover(key, expected_revision) do
    with {:ok, id} <- Ecto.UUID.cast(key),
         true <- is_integer(expected_revision) and expected_revision >= 0 do
      result =
        Repo.transaction(
          fn -> find_or_enqueue(id, expected_revision) end,
          mode: :immediate
        )

      if match?({:ok, _}, result), do: broadcast()
      result
    else
      _ -> {:error, :invalid_command}
    end
  end

  defp find_or_enqueue(id, expected) do
    case Repo.get(Command, id) do
      nil -> enqueue(id, expected)
      %Command{expected_revision: ^expected} = command -> command
      _ -> Repo.rollback(:key_conflict)
    end
  end

  defp enqueue(id, expected) do
    state = if workspace().revision == expected, do: "pending", else: "rejected"

    command =
      Repo.insert!(%Command{
        id: id,
        kind: "discover_tools",
        expected_revision: expected,
        state: state,
        result: if(state == "rejected", do: "stale_revision")
      })

    record("discovery." <> state, %{}, id)
    command
  end

  def claim(now \\ System.system_time(:millisecond)) do
    Repo.transaction(
      fn ->
        command =
          Repo.one(
            from c in Command,
              where: c.state == "pending" or (c.state == "running" and c.lease_until < ^now),
              order_by: c.inserted_at,
              limit: 1
          )

        case command do
          nil ->
            nil

          %{attempts: count} = command when count >= 3 ->
            failed =
              Repo.update!(
                Ecto.Changeset.change(command,
                  state: "failed",
                  result: "retry_limit",
                  lease_until: nil
                )
              )

            record("discovery.failed", %{"reason" => "retry_limit"}, command.id)
            failed

          command ->
            claimed =
              Repo.update!(
                Ecto.Changeset.change(command,
                  state: "running",
                  attempts: command.attempts + 1,
                  lease_until: now + 10_000
                )
              )

            record("discovery.started", %{"attempt" => claimed.attempts}, claimed.id)
            claimed
        end
      end,
      mode: :immediate
    )
    |> tap(fn result -> if match?({:ok, %Command{}}, result), do: broadcast() end)
  end

  def finish(%Command{} = claim, tools) when is_map(tools) do
    result =
      Repo.transaction(
        fn ->
          current = Repo.get!(Command, claim.id)

          unless current.state == "running" and current.attempts == claim.attempts do
            Repo.rollback(:lost_claim)
          end

          workspace = workspace()

          if workspace.revision != claim.expected_revision do
            command =
              Repo.update!(
                Ecto.Changeset.change(current,
                  state: "rejected",
                  result: "stale_revision",
                  lease_until: nil
                )
              )

            record("discovery.rejected", %{"reason" => "stale_revision"}, claim.id)
            command
          else
            Repo.update!(
              Ecto.Changeset.change(workspace,
                revision: workspace.revision + 1,
                tools: tools,
                checked_at: DateTime.utc_now()
              )
            )

            command =
              Repo.update!(
                Ecto.Changeset.change(current,
                  state: "completed",
                  result: "checked",
                  lease_until: nil
                )
              )

            record(
              "discovery.completed",
              %{"found" => Enum.count(tools, fn {_, value} -> value["status"] == "found" end)},
              claim.id
            )

            command
          end
        end,
        mode: :immediate
      )

    if match?({:ok, _}, result), do: broadcast()
    result
  end

  def record(kind, data \\ %{}, command_id \\ nil) do
    Repo.insert!(%Event{
      kind: kind,
      data: data,
      command_id: command_id,
      occurred_at: DateTime.utc_now()
    })
  end

  def broadcast, do: Phoenix.PubSub.broadcast(Cuckoding.PubSub, "foundation", :updated)
end
