defmodule Cuckoding.Planning do
  @moduledoc "Consented brief and document proposals using the frozen Speculator; no delivery authority."
  import Ecto.Query
  alias Cuckoding.{Codex, Command, Foundation, Repo, Storage, Tabulae, Team, TeamAssignments}

  def history(tabula_id) do
    Repo.all(
      from c in Command,
        where:
          c.kind == "plan_tabula" and
            fragment("json_extract(?, '$.tabula_id')", c.payload) == ^tabula_id,
        order_by: [
          desc: fragment("? IN ('pending', 'running', 'cancelling')", c.state),
          desc: c.inserted_at
        ],
        limit: 5
    )
  end

  alias Cuckoding.PlanningDocuments

  def setup(board, preview_id \\ nil) do
    documents = PlanningDocuments.selected(board, preview_id)
    team = TeamAssignments.assigned(board)
    role = Enum.find(team.definition["roles"], &(&1["id"] == "speculator"))
    catalog = Team.catalog()

    if match?({:ok, _}, documents) and role["agent"] == "codex" and
         Team.binding_status(role, catalog) in [:untested, :check_passed] do
      model = Enum.find(catalog.models, &(&1["id"] == role["model_id"]))
      connection = Foundation.workspace().connection

      payload =
        Map.merge(Map.take(connection, ~w(identity fetched_at)), %{
          "connection_command_id" => connection["command_id"],
          "model_id" => model["id"],
          "model" => model["model"],
          "effort" => model["default_effort"],
          "role" => role,
          "team_revision_id" => team.id,
          "arena_id" => board.arena_id,
          "tabula_id" => board.id,
          "grant" => "scratch-read-only-v1",
          "contract" => "brief-plan-v1",
          "document_preview_id" => preview_id,
          "documents" => elem(documents, 1)
        })

      %{
        team_id: team.id,
        role: role,
        payload: payload,
        token: Base.encode16(:crypto.hash(:sha256, :erlang.term_to_binary(payload)))
      }
    else
      %{team_id: team.id, role: role, payload: nil, token: nil}
    end
  end

  def request(key, arena_id, tabula_id, brief, token, confirmed, preview_id \\ nil) do
    with {:ok, key} <- Ecto.UUID.cast(key),
         {:ok, arena_id} <- Ecto.UUID.cast(arena_id),
         %{} = board <- Tabulae.get(arena_id, tabula_id),
         true <- text?(brief, 8_000),
         true <- confirmed == true and is_binary(token) and byte_size(token) == 64 do
      input = %{
        "arena_id" => arena_id,
        "tabula_id" => board.id,
        "brief" => brief,
        "setup_token" => token,
        "document_preview_id" => preview_id
      }

      transaction(fn -> enqueue(key, board, input) end)
    else
      _ -> {:error, "planning_confirmation_required"}
    end
  end

  defp enqueue(key, board, input) do
    case Repo.get(Command, key) do
      nil ->
        setup = setup(board, input["document_preview_id"])

        reason = rejection(setup, input)

        command =
          Repo.insert!(%Command{
            id: key,
            kind: "plan_tabula",
            expected_revision: 0,
            payload: Map.merge(setup.payload || %{}, input),
            state: if(reason, do: "rejected", else: "pending"),
            result: reason
          })

        Foundation.record(
          "planning.#{command.state}",
          %{"tabula_id" => board.id, "reason" => reason},
          key
        )

        command

      %Command{kind: "plan_tabula"} = command ->
        if Map.take(command.payload, Map.keys(input)) == input,
          do: command,
          else: Repo.rollback(:key_conflict)

      _ ->
        Repo.rollback(:key_conflict)
    end
  end

  defp rejection(setup, input) do
    cond do
      is_nil(setup.token) or setup.token != input["setup_token"] -> "planning_setup_changed"
      Foundation.pending?() -> "profile_busy"
      true -> nil
    end
  end

  def execute(command) do
    payload = command.payload

    if Foundation.model_check_current?(payload) do
      Codex.plan(
        payload["identity"],
        Storage.codex_profile!(),
        Storage.probe_directory!(command.id, command.attempts),
        Map.merge(Map.take(payload, ~w(model effort brief documents)), %{
          "request_id" => command.id,
          "instructions" => payload["role"]["instructions"]
        }),
        fn -> Foundation.probe_active?(command) end
      )
    else
      %{"status" => "model_unavailable"}
    end
  rescue
    _ -> %{"status" => "launch_failed"}
  end

  def finish(claim, result) do
    transaction(fn ->
      current = Repo.get!(Command, claim.id)

      unless current.state in ~w(running cancelling) and current.attempts == claim.attempts,
        do: Repo.rollback(:lost_claim)

      {state, result} = outcome(current, claim, result |> Jason.encode!() |> normalize())

      saved =
        Repo.update!(
          Ecto.Changeset.change(current,
            state: state,
            result: result["status"],
            payload: Map.put(current.payload, "observation", result),
            lease_until: nil
          )
        )

      Foundation.record(
        "planning.#{state}",
        Map.merge(
          Map.take(result, ~w(status pid spawned_at_ms elapsed_ms)),
          %{
            "tabula_id" => claim.payload["tabula_id"],
            "task_count" => length(get_in(result, ["proposal", "tasks"]) || [])
          }
        ),
        claim.id
      )

      saved
    end)
  end

  defp outcome(%{state: "cancelling"}, _, result) do
    status =
      if result["status"] == "cleanup_uncertain", do: "cleanup_uncertain", else: "cancelled"

    {"cancelled", Map.put(Map.take(result, ~w(pid spawned_at_ms elapsed_ms)), "status", status)}
  end

  defp outcome(_, claim, %{"status" => "planned"} = result) do
    if matching?(claim, result),
      do: {"completed", result},
      else: {"failed", %{"status" => "model_mismatch"}}
  end

  defp outcome(_, _, result), do: {"failed", result}

  defp matching?(claim, result) do
    result["request_id"] == claim.id and result["requested_model"] == claim.payload["model"] and
      result["observed_model"] == claim.payload["model"] and
      result["effort"] == claim.payload["effort"] and
      Foundation.model_check_current?(claim.payload) and
      Foundation.verified_executable() == {:ok, claim.payload["identity"]}
  end

  def normalize(bytes) when is_binary(bytes) and byte_size(bytes) <= 65_536 do
    case Jason.decode(bytes) do
      {:ok, %{"status" => "planned", "proposal" => proposal, "request_id" => id} = result} ->
        receipt =
          result
          |> Map.drop(~w(proposal request_id))
          |> Map.put("status", "passed")
          |> Jason.encode!()
          |> Codex.normalize_model_check()

        if receipt["status"] == "passed" and match?({:ok, _}, Ecto.UUID.cast(id)) and
             valid_proposal?(proposal),
           do:
             Map.merge(receipt, %{
               "status" => "planned",
               "proposal" => proposal,
               "request_id" => id
             }),
           else: %{"status" => "invalid_response"}

      {:ok, %{"status" => "passed"}} ->
        %{"status" => "invalid_response"}

      _ ->
        Codex.normalize_model_check(bytes)
    end
  end

  def normalize(_), do: %{"status" => "invalid_output"}

  def proposal(%Command{
        kind: "plan_tabula",
        state: "completed",
        result: "planned",
        payload: payload
      }) do
    result = payload["observation"] |> Jason.encode!() |> normalize()
    result["proposal"]
  end

  def proposal(_), do: nil

  defp valid_proposal?(%{"summary" => summary, "tasks" => tasks} = proposal)
       when is_list(tasks) and length(tasks) in 1..6 do
    map_size(proposal) == 2 and text?(summary, 2_000) and Enum.all?(tasks, &valid_task?/1) and
      length(Enum.uniq_by(tasks, &String.downcase(String.trim(&1["title"])))) == length(tasks)
  end

  defp valid_proposal?(_), do: false

  defp valid_task?(
         %{"title" => title, "description" => description, "criteria" => criteria} = task
       ),
       do:
         map_size(task) == 3 and text?(title, 120) and not String.contains?(title, ["\n", "\t"]) and
           text?(description, 4_000) and text?(criteria, 2_000)

  defp valid_task?(_), do: false

  defp text?(text, max) when is_binary(text),
    do:
      byte_size(text) in 1..max and String.valid?(text) and String.trim(text) != "" and
        not Regex.match?(~r/[\x00-\x08\x0B-\x1F\x7F]/, text)

  defp text?(_, _), do: false

  defp transaction(fun) do
    result = Repo.transaction(fun, mode: :immediate)
    if match?({:ok, _}, result), do: Foundation.broadcast()
    result
  end
end
