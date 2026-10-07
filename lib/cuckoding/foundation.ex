defmodule Cuckoding.Foundation do
  @moduledoc "Idempotent setup commands and their committed public event stream."
  import Ecto.Query
  alias Cuckoding.{Codex, Command, Event, Repo, Workspace}

  def workspace, do: Repo.get!(Workspace, 1)
  def events, do: Repo.all(from e in Event, order_by: [desc: e.id], limit: 10)
  def pending?, do: Repo.exists?(from c in Command, where: c.state in ["pending", "running"])

  def pending_probe do
    Repo.one(
      from c in Command,
        where: c.kind == "probe_codex" and c.state in ["pending", "running"],
        order_by: c.inserted_at,
        limit: 1
    )
  end

  def last_probe do
    Repo.one(
      from c in Command, where: c.kind == "probe_codex", order_by: [desc: c.inserted_at], limit: 1
    )
  end

  def probe_active?(claim) do
    Repo.exists?(
      from c in Command,
        where: c.id == ^claim.id and c.state == "running" and c.attempts == ^claim.attempts
    )
  end

  def check_codex(key, expected, path, confirmed) do
    with true <- confirmed == true,
         {:ok, identity} <- Codex.executable(path) do
      command(key, expected, "probe_codex", identity)
    else
      false -> {:error, :confirmation_required}
      error -> error
    end
  end

  def cancel_probe(id) do
    case Ecto.UUID.cast(id) do
      {:ok, id} ->
        Repo.transaction(fn -> cancel_command(Repo.get(Command, id)) end, mode: :immediate)
        |> tap(fn _ -> broadcast() end)

      _ ->
        {:error, :invalid_command}
    end
  end

  defp cancel_command(%Command{kind: "probe_codex", state: state} = command)
       when state in ["pending", "running"] do
    Repo.update!(
      Ecto.Changeset.change(command, state: "cancelled", result: "cancelled", lease_until: nil)
    )

    record("codex.cancelled", %{}, command.id)
  end

  defp cancel_command(_), do: :ok

  def discover(key, expected_revision) do
    command(key, expected_revision, "discover_tools", %{})
  end

  defp command(key, expected_revision, kind, payload) do
    with {:ok, id} <- Ecto.UUID.cast(key),
         true <- is_integer(expected_revision) and expected_revision >= 0 do
      result =
        Repo.transaction(
          fn -> find_or_enqueue(id, expected_revision, kind, payload) end,
          mode: :immediate
        )

      if match?({:ok, _}, result), do: broadcast()
      result
    else
      _ -> {:error, :invalid_command}
    end
  end

  defp find_or_enqueue(id, expected, kind, payload) do
    case Repo.get(Command, id) do
      nil -> enqueue(id, expected, kind, payload)
      %Command{expected_revision: ^expected, kind: ^kind, payload: ^payload} = command -> command
      _ -> Repo.rollback(:key_conflict)
    end
  end

  defp enqueue(id, expected, kind, payload) do
    state = if workspace().revision == expected, do: "pending", else: "rejected"

    command =
      Repo.insert!(%Command{
        id: id,
        kind: kind,
        payload: payload,
        expected_revision: expected,
        state: state,
        result: if(state == "rejected", do: "stale_revision")
      })

    record(prefix(kind) <> state, %{}, id)
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

          %{kind: "probe_codex", state: "running"} = command ->
            failed =
              Repo.update!(
                Ecto.Changeset.change(command,
                  state: "failed",
                  result: "interrupted",
                  lease_until: nil
                )
              )

            record("codex.interrupted", %{}, command.id)
            failed

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

            record(
              prefix(claimed.kind) <> "started",
              %{"attempt" => claimed.attempts},
              claimed.id
            )

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

            record(prefix(claim.kind) <> "rejected", %{"reason" => "stale_revision"}, claim.id)
            command
          else
            {fields, data} = projection(claim, tools)

            Repo.update!(
              Ecto.Changeset.change(workspace, [{:revision, workspace.revision + 1} | fields])
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
              prefix(claim.kind) <> "completed",
              data,
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

  defp projection(%{kind: "discover_tools"}, tools) do
    {[tools: tools, checked_at: DateTime.utc_now()],
     %{"found" => Enum.count(tools, fn {_, value} -> value["status"] == "found" end)}}
  end

  defp projection(%{kind: "probe_codex"} = claim, result) do
    result = Map.take(result, ~w(status version pid spawned_at_ms elapsed_ms))

    public =
      Map.merge(result, %{
        "path" => claim.payload["path"],
        "checked_at" => DateTime.to_iso8601(DateTime.utc_now()),
        "authorization" => "not_connected",
        "command_id" => claim.id
      })

    {[codex: public], Map.take(public, ~w(status version pid spawned_at_ms elapsed_ms))}
  end

  defp prefix("discover_tools"), do: "discovery."
  defp prefix("probe_codex"), do: "codex."

  def broadcast, do: Phoenix.PubSub.broadcast(Cuckoding.PubSub, "foundation", :updated)
end
