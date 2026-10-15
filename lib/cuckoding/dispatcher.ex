defmodule Cuckoding.Dispatcher do
  @moduledoc "Dispatch one monitored setup task; SQLite owns the queue and expiring claims."
  use GenServer
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  @impl true
  def init(options) do
    {:ok, _} = Cuckoding.Foundation.recover()
    Cuckoding.Codex.init_login_links()
    Phoenix.PubSub.subscribe(Cuckoding.PubSub, "foundation")
    send(self(), :tick)
    {:ok, %{job: nil, executor: Keyword.get(options, :executor, &execute/2)}}
  end

  @impl true
  def handle_info(:updated, state), do: {:noreply, state}

  def handle_info(:tick, %{job: nil} = state) do
    job =
      case Cuckoding.Foundation.claim() do
        {:ok, %{state: "running"} = command} ->
          {start_task(command, state.executor), command}

        _ ->
          Process.send_after(self(), :tick, 500)
          nil
      end

    {:noreply, %{state | job: job}}
  end

  def handle_info({ref, result}, %{job: {%Task{ref: ref}, command}} = state) do
    Process.demonitor(ref, [:flush])
    Cuckoding.Codex.clear_login_link()
    Cuckoding.Foundation.finish(command, result)
    send(self(), :tick)
    {:noreply, %{state | job: nil}}
  end

  def handle_info({:DOWN, ref, :process, _, _}, %{job: {%Task{ref: ref}, command}} = state) do
    Cuckoding.Codex.clear_login_link()
    Cuckoding.Foundation.interrupt(command)
    send(self(), :tick)
    {:noreply, %{state | job: nil}}
  end

  def handle_info({:login_link, pid, url}, %{job: {%Task{pid: pid}, command}} = state) do
    publish_login_link(command, url)
    {:noreply, state}
  end

  def handle_info(_, state), do: {:noreply, state}

  @impl true
  def format_status(status) do
    Map.new(status, fn
      {:log, _} -> {:log, []}
      {key, _} when key in [:message, :state, :reason] -> {key, :redacted}
      entry -> entry
    end)
  end

  defp start_task(command, executor) do
    owner = self()

    Task.Supervisor.async_nolink(Cuckoding.SetupTasks, fn ->
      executor.(command, fn url -> send(owner, {:login_link, self(), url}) end)
    end)
  end

  defp execute(%{kind: "preview_documents"} = command, _progress),
    do: Cuckoding.PlanningDocuments.execute(command)

  defp execute(%{kind: "accept_spec"} = command, _progress),
    do: Cuckoding.Specifications.execute(command)

  defp execute(%{kind: "plan_tabula"} = command, _progress),
    do: Cuckoding.Planning.execute(command)

  defp execute(%{kind: "discover_tools"}, _progress), do: Cuckoding.Tools.discover()

  defp execute(%{kind: "choose_arena_folder"} = command, _progress),
    do: Cuckoding.NativeHelper.choose_folder(command)

  defp execute(%{kind: kind} = command, _progress)
       when kind in ~w(inspect_arena_git init_arena_git preview_arena_git commit_arena_git worktree_arena_git inspect_worktree_arena_git),
       do: Cuckoding.ArenaGit.execute(command)

  defp execute(%{kind: kind} = command, _progress) when kind in ~w(probe_codex probe_cursor) do
    if Cuckoding.Foundation.workspace().revision == command.expected_revision do
      directory = Cuckoding.Storage.probe_directory!(command.id, command.attempts)

      adapter(command).probe(
        Cuckoding.Foundation.executable_identity(command.payload),
        directory,
        fn ->
          Cuckoding.Foundation.probe_active?(command)
        end
      )
    else
      %{}
    end
  rescue
    _ -> %{"status" => "launch_failed"}
  end

  defp execute(%{kind: kind} = command, _progress)
       when kind in ~w(inspect_codex inspect_cursor) do
    if Cuckoding.Foundation.workspace().revision == command.expected_revision do
      directory = Cuckoding.Storage.codex_profile!(Cuckoding.Foundation.agent_id(command.payload))

      adapter(command).inspect_connection(
        Cuckoding.Foundation.executable_identity(command.payload),
        directory,
        fn ->
          Cuckoding.Foundation.probe_active?(command)
        end
      )
    else
      %{}
    end
  rescue
    _ -> %{"status" => "launch_failed"}
  end

  defp execute(%{kind: kind} = command, progress)
       when kind in ~w(login_codex logout_codex login_cursor logout_cursor) do
    if Cuckoding.Foundation.workspace().revision == command.expected_revision do
      adapter(command).authorize(
        Cuckoding.Foundation.executable_identity(command.payload),
        Cuckoding.Storage.codex_profile!(Cuckoding.Foundation.agent_id(command.payload)),
        if(kind in ~w(login_codex login_cursor), do: :login, else: :logout),
        fn -> Cuckoding.Foundation.probe_active?(command) end,
        progress
      )
    else
      %{"status" => "executable_changed"}
    end
  rescue
    _ -> %{"status" => "launch_failed"}
  end

  defp execute(%{kind: "check_codex_model"} = command, _progress) do
    if Cuckoding.Foundation.workspace().revision == command.expected_revision and
         Cuckoding.Foundation.model_check_current?(command.payload) do
      Cuckoding.Codex.check_model(
        command.payload["identity"],
        Cuckoding.Storage.codex_profile!(Cuckoding.Foundation.agent_id(command.payload)),
        Cuckoding.Storage.probe_directory!(command.id, command.attempts),
        command.payload["model"],
        command.payload["effort"],
        fn -> Cuckoding.Foundation.probe_active?(command) end
      )
    else
      %{"status" => "model_unavailable"}
    end
  rescue
    _ -> %{"status" => "launch_failed"}
  end

  defp execute(%{kind: "check_codex_isolation"} = command, _progress) do
    if Cuckoding.Foundation.workspace().revision == command.expected_revision and
         Cuckoding.Foundation.isolation_current?(command.payload) do
      Cuckoding.Codex.check_isolation(
        command.payload["identity"],
        Cuckoding.Storage.probe_directory!(command.id, command.attempts),
        fn -> Cuckoding.Foundation.probe_active?(command) end
      )
    else
      %{"status" => "executable_changed"}
    end
  rescue
    _ -> %{"status" => "launch_failed"}
  end

  defp adapter(command),
    do:
      Cuckoding.Agents.adapter(
        Cuckoding.Agents.kind(Cuckoding.Foundation.agent_id(command.payload))
      )

  defp publish_login_link(command, url) do
    kind = Cuckoding.Agents.kind(Cuckoding.Foundation.agent_id(command.payload))

    if Cuckoding.Codex.valid_login_url?(url, kind) and
         Cuckoding.Foundation.login_waiting(command) == :ok do
      Cuckoding.Codex.put_login_link(
        command.id,
        url,
        kind
      )

      Cuckoding.Foundation.broadcast()
    end
  end
end
