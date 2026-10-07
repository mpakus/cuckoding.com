defmodule Cuckoding.Dispatcher do
  @moduledoc "One supervised dispatcher; SQLite owns the queue and expiring claims."
  use GenServer
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  @impl true
  def init(_) do
    Cuckoding.Codex.init_login_links()
    Phoenix.PubSub.subscribe(Cuckoding.PubSub, "foundation")
    send(self(), :tick)
    {:ok, nil}
  end

  @impl true
  def handle_info(:updated, state), do: {:noreply, state}
  def handle_info({port, _}, state) when is_port(port), do: {:noreply, state}

  # ponytail: setup is serialized; per-profile workers when multiple connections exist.
  def handle_info(:tick, state) do
    case Cuckoding.Foundation.claim() do
      {:ok, %{state: "running"} = command} ->
        result = execute(command)
        Cuckoding.Codex.clear_login_link()
        Cuckoding.Foundation.finish(command, result)

      _ ->
        :ok
    end

    Process.send_after(self(), :tick, 500)
    {:noreply, state}
  end

  defp execute(%{kind: "plan_tabula"} = command), do: Cuckoding.Planning.execute(command)

  defp execute(%{kind: "discover_tools"}), do: Cuckoding.Tools.discover()

  defp execute(%{kind: "choose_arena_folder"} = command),
    do: Cuckoding.NativeHelper.choose_folder(command)

  defp execute(%{kind: kind} = command)
       when kind in ~w(inspect_arena_git init_arena_git preview_arena_git commit_arena_git),
       do: Cuckoding.ArenaGit.execute(command)

  defp execute(%{kind: "probe_codex"} = command) do
    if Cuckoding.Foundation.workspace().revision == command.expected_revision do
      directory = Cuckoding.Storage.probe_directory!(command.id, command.attempts)

      Cuckoding.Codex.probe(command.payload, directory, fn ->
        Cuckoding.Foundation.probe_active?(command)
      end)
    else
      %{}
    end
  rescue
    _ -> %{"status" => "launch_failed"}
  end

  defp execute(%{kind: "inspect_codex"} = command) do
    if Cuckoding.Foundation.workspace().revision == command.expected_revision do
      directory = Cuckoding.Storage.codex_profile!()

      Cuckoding.Codex.inspect_connection(command.payload, directory, fn ->
        Cuckoding.Foundation.probe_active?(command)
      end)
    else
      %{}
    end
  rescue
    _ -> %{"status" => "launch_failed"}
  end

  defp execute(%{kind: kind} = command) when kind in ["login_codex", "logout_codex"] do
    if Cuckoding.Foundation.workspace().revision == command.expected_revision do
      Cuckoding.Codex.authorize(
        command.payload,
        Cuckoding.Storage.codex_profile!(),
        if(kind == "login_codex", do: :login, else: :logout),
        fn -> Cuckoding.Foundation.probe_active?(command) end,
        fn url -> publish_login_link(command, url) end
      )
    else
      %{"status" => "executable_changed"}
    end
  rescue
    _ -> %{"status" => "launch_failed"}
  end

  defp execute(%{kind: "check_codex_model"} = command) do
    if Cuckoding.Foundation.workspace().revision == command.expected_revision and
         Cuckoding.Foundation.model_check_current?(command.payload) do
      Cuckoding.Codex.check_model(
        command.payload["identity"],
        Cuckoding.Storage.codex_profile!(),
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

  defp publish_login_link(command, url) do
    if Cuckoding.Foundation.login_waiting(command) == :ok do
      Cuckoding.Codex.put_login_link(command.id, url)
      Cuckoding.Foundation.broadcast()
    end
  end
end
