defmodule Cuckoding.Execution.CommandDispatcher do
  @moduledoc """
  Claims committed commands, executes handlers outside the claim transaction, and records outcomes.
  """

  import Ecto.Query

  alias Cuckoding.Execution.Command
  alias Cuckoding.Execution.UnconfiguredCommandHandler
  alias Cuckoding.Repo

  @max_batch_size 100
  @max_backoff_ms 60_000

  def dispatch(command_id, options \\ []) do
    now = Keyword.get(options, :now, Cuckoding.Clock.wall_now())
    handler = Keyword.get(options, :handler, configured_handler())

    case claim(command_id, now) do
      {:ok, {:claimed, command}} -> execute(command, handler, now)
      {:ok, {_status, command}} -> {:ok, command}
      {:error, reason} -> {:error, reason}
    end
  end

  def dispatch_due(options \\ []) do
    now = Keyword.get(options, :now, Cuckoding.Clock.wall_now())
    limit = options |> Keyword.get(:limit, @max_batch_size) |> min(@max_batch_size)

    command_ids =
      Repo.all(
        from(command in Command,
          where: command.state == "pending" and command.not_before <= ^now,
          order_by: [asc: command.not_before, asc: command.id],
          limit: ^limit,
          select: command.id
        )
      )

    Enum.map(command_ids, &dispatch(&1, options))
  end

  def recover_interrupted(now \\ Cuckoding.Clock.wall_now()) do
    Repo.update_all(
      from(command in Command, where: command.state == "running"),
      set: [state: "pending", not_before: now, last_error: "interrupted before completion"],
      inc: [attempts: -1]
    )
  end

  def configured_handler do
    Application.get_env(:cuckoding, :command_handler, UnconfiguredCommandHandler)
  end

  def backoff_ms(attempt) when is_integer(attempt) and attempt > 0 do
    min(Integer.pow(2, attempt - 1) * 1_000, @max_backoff_ms)
  end

  defp claim(command_id, now) do
    Repo.transaction(fn -> claim_command(Repo.get(Command, command_id), now) end)
  end

  defp claim_command(nil, _now), do: Repo.rollback(:not_found)

  defp claim_command(%Command{state: state} = command, _now)
       when state in ["succeeded", "failed"],
       do: {:terminal, command}

  defp claim_command(%Command{state: "running"} = command, _now), do: {:running, command}

  defp claim_command(%Command{not_before: not_before} = command, now) do
    if DateTime.after?(not_before, now), do: {:not_due, command}, else: claim_pending(command)
  end

  defp claim_pending(command) do
    command =
      command
      |> Command.state_changeset(%{
        state: "running",
        attempts: command.attempts + 1,
        last_error: nil
      })
      |> Repo.update!()

    {:claimed, command}
  end

  defp execute(command, handler, now) do
    case handler.execute(command) do
      {:ok, result} when is_map(result) -> succeed(command, result)
      {:error, reason} -> fail(command, reason, now)
    end
  end

  defp succeed(command, result) do
    command
    |> Command.state_changeset(%{state: "succeeded", result: result, last_error: nil})
    |> Repo.update()
  end

  defp fail(command, reason, now) do
    exhausted? = command.attempts >= command.max_attempts

    attrs = %{
      state: if(exhausted?, do: "failed", else: "pending"),
      not_before:
        if(exhausted?,
          do: now,
          else: DateTime.add(now, backoff_ms(command.attempts), :millisecond)
        ),
      last_error: public_failure_label(reason)
    }

    command |> Command.state_changeset(attrs) |> Repo.update()
  end

  defp public_failure_label(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp public_failure_label({reason, _details}) when is_atom(reason), do: Atom.to_string(reason)
  defp public_failure_label(%{__struct__: module}), do: inspect(module)
  defp public_failure_label(_reason), do: "command failed"
end
