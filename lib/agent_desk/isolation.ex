defmodule AgentDesk.Isolation do
  @moduledoc """
  Per-agent isolation names and app-owned templates for databases, Compose, and ports.

  Templates live under the session data directory, never in the user's primary tree.
  """

  alias AgentDesk.Agents.Session
  alias AgentDesk.Resources.Manager
  alias AgentDesk.Scope
  alias AgentDesk.Storage

  @port_range 41_000..41_199

  @spec test_database(Session.t()) :: String.t()
  def test_database(%Session{id: id}), do: "agentdesk_test_" <> short(id)

  @spec test_schema(Session.t()) :: String.t()
  def test_schema(%Session{id: id}), do: "agent_" <> short(id)

  @spec test_partition(Session.t()) :: String.t()
  def test_partition(%Session{id: id}), do: "ex_unit_" <> short(id)

  @spec compose_project(Session.t()) :: String.t()
  def compose_project(%Session{id: id}), do: "agentdesk_" <> short(id)

  @spec dir(Session.t()) :: String.t()
  def dir(%Session{} = session) do
    Path.join(Storage.session_dir(session.project_id, session.id), "isolation")
  end

  @spec assigned_port(Session.t()) :: integer() | nil
  def assigned_port(%Session{id: id}) do
    id
    |> Manager.list_owned()
    |> Enum.find_value(&port_number/1)
  end

  @spec env(Session.t()) :: %{String.t() => String.t()}
  def env(%Session{} = session) do
    base = %{
      "AGENTDESK_TEST_DATABASE" => test_database(session),
      "AGENTDESK_TEST_SCHEMA" => test_schema(session),
      "AGENTDESK_TEST_PARTITION" => test_partition(session),
      "MIX_TEST_PARTITION" => test_partition(session),
      "AGENTDESK_COMPOSE_PROJECT" => compose_project(session),
      "AGENTDESK_BIND" => "127.0.0.1"
    }

    case assigned_port(session) do
      nil -> base
      port -> Map.put(base, "AGENTDESK_PORT", Integer.to_string(port))
    end
  end

  @spec profile(Session.t()) :: map()
  def profile(%Session{} = session) do
    %{
      "database" => test_database(session),
      "schema" => test_schema(session),
      "partition" => test_partition(session),
      "compose_project" => compose_project(session),
      "bind" => "127.0.0.1",
      "port" => assigned_port(session),
      "dir" => dir(session),
      "env" => env(session)
    }
  end

  @spec write_templates!(Session.t()) :: String.t()
  def write_templates!(%Session{} = session) do
    dest = dir(session)
    File.mkdir_p!(dest)

    Enum.each(files(session), fn {name, body} ->
      File.write!(Path.join(dest, name), body)
    end)

    dest
  end

  @spec allocate_port(Scope.t()) :: {:ok, integer()} | {:error, term()}
  def allocate_port(%Scope{} = scope) do
    used =
      scope.project.id
      |> Manager.list_project()
      |> Enum.filter(&(&1.resource_type == "port"))
      |> MapSet.new(& &1.resource_key)

    case Enum.find(@port_range, fn n -> not MapSet.member?(used, "tcp:#{n}") end) do
      nil ->
        {:error, :ports_exhausted}

      number ->
        key = "tcp:#{number}"

        case Manager.claim(scope, [%{"type" => "port", "key" => key, "mode" => "exclusive"}],
               reason: "session port"
             ) do
          {:ok, _} -> {:ok, number}
          error -> error
        end
    end
  end

  defp files(%Session{} = session) do
    database = test_database(session)
    schema = test_schema(session)
    partition = test_partition(session)
    compose = compose_project(session)
    env_body = env(session) |> Enum.sort() |> Enum.map_join("\n", fn {k, v} -> "#{k}=#{v}" end)

    [
      {"env", env_body <> "\n"},
      {"postgres.database.sql",
       """
       -- Database-per-agent. Run as a role that can CREATE DATABASE.
       -- Do not apply this against the user's primary checkout from isolated mode.
       CREATE DATABASE #{database};
       """},
      {"postgres.schema.sql",
       """
       -- Schema-per-agent inside a shared database.
       CREATE SCHEMA IF NOT EXISTS #{schema};
       SET search_path TO #{schema};
       """},
      {"elixir.test.exs",
       """
       # Point the session test Repo at Cuckoding isolation env vars.
       # Isolated sessions must not edit the user's primary worktree.
       import Config

       config :your_app, YourApp.Repo,
         hostname: "127.0.0.1",
         database: System.get_env("AGENTDESK_TEST_DATABASE", "#{database}"),
         after_connect: {Postgrex, :query!, ["SET search_path TO " <> System.get_env("AGENTDESK_TEST_SCHEMA", "#{schema}"), []]}

       config :ex_unit, partition: System.get_env("MIX_TEST_PARTITION") || "#{partition}"
       """},
      {"compose.overlay.yaml",
       """
       # Merge with the worktree Compose file. Cuckoding already passes
       # `-p #{compose}` and rejects 0.0.0.0 / host network / privileged.
       name: ${AGENTDESK_COMPOSE_PROJECT}
       x-agentdesk:
         database: ${AGENTDESK_TEST_DATABASE}
         schema: ${AGENTDESK_TEST_SCHEMA}
         partition: ${AGENTDESK_TEST_PARTITION}
         bind: ${AGENTDESK_BIND:-127.0.0.1}
       """}
    ]
  end

  defp port_number(%{resource_type: "port", resource_key: "tcp:" <> rest}) do
    case Integer.parse(rest) do
      {number, ""} -> number
      _ -> nil
    end
  end

  defp port_number(_), do: nil

  defp short(id) do
    id |> String.replace("-", "") |> String.slice(0, 12)
  end
end
