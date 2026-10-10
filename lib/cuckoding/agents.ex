defmodule Cuckoding.Agents do
  @moduledoc "Named, independent runtime connections; legacy Codex keeps its existing identity."
  import Ecto.Query
  alias Cuckoding.{AgentConnection, Codex, Foundation, Repo}

  def list do
    legacy = get("codex")
    rows = Repo.all(from a in AgentConnection, order_by: a.inserted_at)
    if legacy.codex == %{}, do: rows, else: [legacy | rows]
  end

  def get("codex") do
    workspace = Foundation.workspace()

    %{
      id: "codex",
      name: "Codex",
      kind: "codex",
      codex: workspace.codex,
      connection: workspace.connection
    }
  end

  def get(id) do
    case Ecto.UUID.cast(id) do
      {:ok, id} -> Repo.get(AgentConnection, id)
      _ -> nil
    end
  end

  def display(id) do
    case get(id) do
      %{name: name, kind: kind} -> name <> " · " <> label(kind)
      _ -> "Unassigned"
    end
  end

  def kind(id) do
    case get(id) do
      %{kind: kind} -> kind
      _ -> nil
    end
  end

  def adapter("codex"), do: Codex
  def adapter("cursor"), do: Cuckoding.Cursor

  def label("codex"), do: "Codex"
  def label("cursor"), do: "Cursor"

  def add_and_probe(key, expected, name, kind, path) do
    with {:ok, id} <- Ecto.UUID.cast(key),
         true <- kind in ~w(codex cursor),
         true <-
           is_binary(name) and String.valid?(name) and String.length(String.trim(name)) in 1..60,
         false <- Regex.match?(~r/[\x00-\x1f\x7f]/, name),
         {:ok, _} <- Codex.executable(path) do
      result =
        Repo.transaction(
          fn -> create_and_probe(id, expected, String.trim(name), kind, path) end,
          mode: :immediate
        )

      if match?({:ok, _}, result), do: Foundation.broadcast()
      result
    else
      _ -> {:error, :invalid_agent}
    end
  end

  defp create_and_probe(id, expected, name, kind, path) do
    ensure_connection(id, expected, name, kind)

    case Foundation.check_codex(id, expected, path, true, id) do
      {:ok, command} -> command
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp ensure_connection(id, expected, name, kind) do
    case get(id) do
      nil ->
        if Foundation.workspace().revision != expected or Foundation.pending?(),
          do: Repo.rollback(:stale_revision)

        Repo.insert!(%AgentConnection{id: id, name: name, kind: kind})
        Foundation.record("agent.added", %{"agent_id" => id, "kind" => kind})

      %{name: ^name, kind: ^kind} ->
        :ok

      _ ->
        Repo.rollback(:key_conflict)
    end
  end

  def project("codex", fields), do: fields

  def project(id, fields) do
    Repo.update!(Ecto.Changeset.change(Repo.get!(AgentConnection, id), fields))
    []
  end
end
