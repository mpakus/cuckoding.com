defmodule Cuckoding.ProjectChecks do
  @moduledoc "User-approved check declarations. Saving never grants or launches execution."
  import Ecto.Query
  alias Cuckoding.{Arena, CheckRevision, Command, Foundation, Repo}

  @fields ~w(id name executable arguments directory timeout_seconds)

  def current(arena_id) do
    Repo.one(
      from r in CheckRevision,
        where: r.arena_id == ^arena_id,
        order_by: [desc: r.revision],
        limit: 1
    ) ||
      %CheckRevision{arena_id: arena_id, revision: 0, definition: definition([])}
  end

  def history(arena_id),
    do:
      Repo.all(
        from r in CheckRevision,
          where: r.arena_id == ^arena_id,
          order_by: [desc: r.revision],
          limit: 5
      )

  def preview(checks) do
    if valid_checks?(checks), do: {:ok, definition(checks)}, else: {:error, "invalid_checks"}
  end

  def digest(definition),
    do:
      Base.encode16(:crypto.hash(:sha256, :erlang.term_to_binary(definition, [:deterministic])),
        case: :lower
      )

  def save(key, arena_id, expected, checks, confirmed) do
    with {:ok, key} <- Ecto.UUID.cast(key),
         {:ok, arena_id} <- Ecto.UUID.cast(arena_id),
         true <- is_integer(expected) and expected >= 0,
         {:ok, definition} <- preview(checks) do
      payload = %{
        "arena_id" => arena_id,
        "definition" => definition,
        "confirmed" => confirmed == true
      }

      result = Repo.transaction(fn -> command(key, expected, payload) end, mode: :immediate)
      if match?({:ok, _}, result), do: Foundation.broadcast()

      case result do
        {:ok, %Command{state: "completed"}} -> {:ok, Repo.get_by!(CheckRevision, command_id: key)}
        {:ok, %Command{result: reason}} -> {:error, reason}
        error -> error
      end
    else
      _ -> {:error, "invalid_checks"}
    end
  end

  defp command(key, expected, payload) do
    case Repo.get(Command, key) do
      nil -> persist(key, expected, payload)
      %Command{kind: "save_checks", expected_revision: ^expected, payload: ^payload} = c -> c
      _ -> Repo.rollback(:key_conflict)
    end
  end

  defp persist(key, expected, payload) do
    previous = current(payload["arena_id"])
    reason = rejection(previous, expected, payload)

    command =
      Repo.insert!(%Command{
        id: key,
        kind: "save_checks",
        expected_revision: expected,
        payload: payload,
        state: if(reason, do: "rejected", else: "completed"),
        result: reason
      })

    if is_nil(reason) do
      Repo.insert!(%CheckRevision{
        arena_id: payload["arena_id"],
        command_id: key,
        revision: expected + 1,
        definition: payload["definition"],
        inserted_at: DateTime.utc_now()
      })
    end

    Foundation.record(
      "checks.#{command.state}",
      %{
        "arena_id" => payload["arena_id"],
        "previous_revision" => expected,
        "revision" => if(is_nil(reason), do: expected + 1),
        "check_count" => length(payload["definition"]["checks"]),
        "reason" => reason
      },
      key
    )

    command
  end

  defp rejection(previous, expected, payload) do
    cond do
      not Repo.exists?(from a in Arena, where: a.id == ^payload["arena_id"]) -> "scope_missing"
      not payload["confirmed"] -> "confirmation_required"
      previous.revision != expected -> "stale_checks"
      previous.definition == payload["definition"] -> "checks_unchanged"
      true -> nil
    end
  end

  defp definition(checks), do: %{"version" => 1, "execution" => "disabled", "checks" => checks}

  defp valid_checks?(checks) when is_list(checks) and length(checks) <= 8 do
    Enum.all?(checks, &valid_check?/1) and
      length(Enum.uniq_by(checks, & &1["id"])) == length(checks) and
      length(Enum.uniq_by(checks, &String.downcase(String.trim(&1["name"])))) == length(checks)
  end

  defp valid_checks?(_), do: false

  defp valid_check?(check) when is_map(check) do
    Enum.sort(Map.keys(check)) == Enum.sort(@fields) and
      canonical_id?(check["id"]) and valid_name?(check["name"]) and
      valid_executable?(check["executable"]) and valid_arguments?(check["arguments"]) and
      relative_directory?(check["directory"]) and is_integer(check["timeout_seconds"]) and
      check["timeout_seconds"] in 1..1800
  end

  defp valid_check?(_), do: false

  defp valid_name?(name),
    do: text?(name, 240) and String.length(name) in 1..60 and String.trim(name) != ""

  defp valid_executable?(name),
    do:
      text?(name, 80) and name != "rtk" and
        Regex.match?(~r/\A[A-Za-z0-9][A-Za-z0-9._+\-]*\z/, name)

  defp canonical_id?(id) when is_binary(id), do: Ecto.UUID.cast(id) == {:ok, id}
  defp canonical_id?(_), do: false

  defp valid_arguments?(args) when is_list(args) and length(args) <= 16,
    do: Enum.all?(args, &(text?(&1, 256) and &1 != ""))

  defp valid_arguments?(_), do: false

  defp relative_directory?("."), do: true

  defp relative_directory?(path) do
    text?(path, 240) and not String.contains?(path, "\\") and
      Enum.all?(
        String.split(path, "/"),
        &(&1 not in ["", ".", ".."] and not String.starts_with?(&1, "~"))
      )
  end

  defp text?(value, max) when is_binary(value),
    do:
      byte_size(value) <= max and String.valid?(value) and
        not Regex.match?(~r/[\x00-\x1F\x7F]/, value)

  defp text?(_, _), do: false
end
