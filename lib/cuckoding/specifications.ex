defmodule Cuckoding.Specifications do
  @moduledoc "Revision-bound local Markdown specifications; acceptance is not execution authority."
  import Ecto.Query
  alias Cuckoding.{Command, DraftTask, Foundation, Repo, Storage, Tabulae}

  def history(tabula_id, task_id) do
    Repo.all(
      from c in Command,
        where:
          c.kind == "accept_spec" and
            fragment("json_extract(?, '$.tabula_id')", c.payload) == ^tabula_id and
            fragment("json_extract(?, '$.task_id')", c.payload) == ^task_id,
        order_by: [desc: c.inserted_at],
        limit: 5
    )
  end

  def preview(arena_id, tabula_id, task_id, revision) do
    with {:ok, arena_id} <- Ecto.UUID.cast(arena_id),
         {:ok, tabula_id} <- Ecto.UUID.cast(tabula_id),
         {:ok, task_id} <- Ecto.UUID.cast(task_id),
         true <- is_integer(revision) and revision > 0 do
      Repo.transaction(fn -> snapshot(arena_id, tabula_id, task_id, revision) end)
    else
      _ -> {:error, "scope_missing"}
    end
  end

  defp snapshot(arena_id, tabula_id, task_id, revision) do
    board = Tabulae.get(arena_id, tabula_id)
    tasks = if board, do: Tabulae.tasks(board.id), else: []
    task = Enum.find(tasks, &(&1.id == task_id))
    validate_task!(task, revision)

    dependencies =
      Enum.map(task.depends_on, fn id ->
        dependency = Enum.find(tasks, &(&1.id == id)) || Repo.rollback("scope_missing")
        %{"id" => id, "revision" => dependency.revision}
      end)

    source = Tabulae.source(tabula_id, task_id)

    payload = %{
      "version" => 1,
      "arena_id" => arena_id,
      "tabula_id" => tabula_id,
      "task_id" => task_id,
      "draft_revision" => revision,
      "content" => Tabulae.content(task),
      "dependencies" => dependencies,
      "source" => if(source, do: %{"plan_id" => source.plan_id, "index" => source.index}),
      "documents" => if(source, do: source.documents, else: [])
    }

    markdown = markdown(payload)
    if byte_size(markdown) > 262_144, do: Repo.rollback("spec_too_large")
    Map.merge(payload, %{"markdown" => markdown, "sha256" => digest(markdown)})
  end

  defp validate_task!(nil, _), do: Repo.rollback("scope_missing")

  defp validate_task!(%{revision: actual}, expected) when actual != expected,
    do: Repo.rollback("stale_task")

  defp validate_task!(task, _) do
    if String.trim(task.description) == "" or String.trim(task.criteria) == "",
      do: Repo.rollback("criteria_required")
  end

  def request(key, arena_id, tabula_id, task_id, revision, hash, confirmed) do
    with true <- confirmed == true,
         {:ok, key} <- Ecto.UUID.cast(key),
         {:ok, arena_id} <- Ecto.UUID.cast(arena_id),
         {:ok, tabula_id} <- Ecto.UUID.cast(tabula_id),
         {:ok, task_id} <- Ecto.UUID.cast(task_id),
         true <- is_integer(revision) and revision > 0,
         true <- is_binary(hash) and byte_size(hash) == 64 do
      input = %{
        "arena_id" => arena_id,
        "tabula_id" => tabula_id,
        "task_id" => task_id,
        "draft_revision" => revision,
        "sha256" => hash
      }

      transaction(fn -> find_or_enqueue(key, input) end)
    else
      _ -> {:error, "confirmation_required"}
    end
  end

  defp find_or_enqueue(key, input) do
    case Repo.get(Command, key) do
      nil ->
        enqueue(key, input)

      %Command{kind: "accept_spec"} = command ->
        if Map.take(command.payload, Map.keys(input)) == input,
          do: command,
          else: Repo.rollback(:key_conflict)

      _ ->
        Repo.rollback(:key_conflict)
    end
  end

  defp enqueue(key, input) do
    payload =
      snapshot(input["arena_id"], input["tabula_id"], input["task_id"], input["draft_revision"])

    if payload["sha256"] != input["sha256"], do: Repo.rollback("preview_changed")
    if Foundation.pending?(), do: Repo.rollback("setup_busy")

    if Enum.any?(
         history(input["tabula_id"], input["task_id"]),
         &(current?(&1) and match?({:ok, _}, read(&1.id)))
       ),
       do: Repo.rollback("already_accepted")

    command =
      Repo.insert!(%Command{
        id: key,
        kind: "accept_spec",
        expected_revision: input["draft_revision"],
        payload: payload
      })

    Foundation.record("spec.pending", scope(command), key)
    command
  end

  def execute(command) do
    started = System.monotonic_time(:millisecond)

    status =
      cond do
        not Foundation.probe_active?(command) ->
          "cancelled"

        not unchanged?(command.payload) ->
          "preview_changed"

        true ->
          case Storage.write_spec(command.id, command.payload["markdown"]) do
            :ok -> "written"
            {:error, _} -> "artifact_unavailable"
          end
      end

    %{"status" => status, "elapsed_ms" => System.monotonic_time(:millisecond) - started}
  end

  def finish(claim, result) do
    transaction(fn ->
      current = Repo.get!(Command, claim.id)

      unless current.kind == "accept_spec" and current.state in ~w(running cancelling) and
               current.attempts == claim.attempts,
             do: Repo.rollback(:lost_claim)

      status = completion_status(current, result)

      state =
        case status do
          "accepted" -> "completed"
          "cancelled" -> "cancelled"
          _ -> "failed"
        end

      if status == "accepted", do: Tabulae.accept_spec(current)

      observation = %{
        "status" => status,
        "elapsed_ms" => elapsed(result["elapsed_ms"])
      }

      updated =
        Repo.update!(
          Ecto.Changeset.change(current,
            state: state,
            result: status,
            lease_until: nil,
            payload: Map.put(current.payload, "observation", observation)
          )
        )

      Foundation.record("spec.#{state}", Map.merge(scope(current), observation), current.id)
      updated
    end)
  end

  defp elapsed(value) when is_integer(value) and value >= 0, do: value
  defp elapsed(_), do: nil

  defp completion_status(command, result) do
    cond do
      command.state == "cancelling" ->
        "cancelled"

      command.lease_until <= System.system_time(:millisecond) ->
        "interrupted"

      not unchanged?(command.payload) ->
        "preview_changed"

      result["status"] != "written" ->
        "artifact_unavailable"

      Storage.read_spec(command.id, command.payload["sha256"]) !=
          {:ok, command.payload["markdown"]} ->
        "artifact_unavailable"

      true ->
        "accepted"
    end
  end

  def unchanged?(payload) do
    same_revisions?(payload, 0)
  end

  def current?(%Command{state: "completed", result: "accepted", payload: p}) do
    same_revisions?(p, 1)
  end

  def current?(_), do: false

  defp same_revisions?(p, offset) do
    task = Repo.get(DraftTask, p["task_id"])

    task != nil and task.tabula_id == p["tabula_id"] and
      task.revision == p["draft_revision"] + offset and
      Enum.all?(p["dependencies"], fn dependency ->
        case Repo.get(DraftTask, dependency["id"]) do
          %{tabula_id: scope, revision: revision} ->
            scope == p["tabula_id"] and revision == dependency["revision"]

          _ ->
            false
        end
      end)
  end

  def read(id) do
    with {:ok, ^id} <- Ecto.UUID.cast(id),
         %Command{kind: "accept_spec", state: "completed", result: "accepted"} = command <-
           Repo.get(Command, id) do
      Storage.read_spec(command.id, command.payload["sha256"])
    else
      _ -> {:error, :unavailable}
    end
  end

  def digest(text), do: Base.encode16(:crypto.hash(:sha256, text), case: :lower)

  defp scope(command),
    do: Map.take(command.payload, ~w(arena_id tabula_id task_id draft_revision))

  defp markdown(p) do
    content = p["content"]

    dependencies =
      Enum.map_join(p["dependencies"], "\n", &"- #{&1["id"]} · revision #{&1["revision"]}")

    documents =
      Enum.map_join(p["documents"], "\n", fn doc ->
        "### Source snapshot\n\n" <>
          literal(doc["path"]) <>
          "\nSHA-256: #{doc["sha256"]}\n\n" <> literal(doc["text"])
      end)

    """
    # Task specification

    Cuckoding specification format 1. Acceptance records intent, not execution or completion.

    Arena: #{p["arena_id"]}
    Tabula: #{p["tabula_id"]}
    Task: #{p["task_id"]}
    Source draft revision: #{p["draft_revision"]}

    ## Title

    #{literal(content["title"])}
    ## Description

    #{literal(content["description"])}
    ## Acceptance criteria

    #{literal(content["criteria"])}
    ## Prerequisite revisions

    #{if dependencies == "", do: "None.", else: dependencies}

    ## Original proposal sources

    These snapshots describe the original import. They do not prove later edits or citation meaning.
    #{if p["source"], do: "Proposal: #{p["source"]["plan_id"]} · suggestion #{p["source"]["index"] + 1}", else: "Manually created draft."}

    #{if documents == "", do: "No task-specific source snapshots.", else: documents}
    """
  end

  # Literal fenced text keeps user/model Markdown, HTML and links inert in this artifact.
  defp literal(text) do
    longest =
      Regex.scan(~r/`+/, text)
      |> List.flatten()
      |> Enum.map(&byte_size/1)
      |> Enum.max(fn -> 2 end)

    fence = String.duplicate("`", max(3, longest + 1))
    "#{fence}text\n#{text}\n#{fence}\n"
  end

  defp transaction(fun) do
    result = Repo.transaction(fun, mode: :immediate)
    if match?({:ok, _}, result), do: Foundation.broadcast()
    result
  end
end
