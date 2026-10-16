defmodule CuckodingWeb.AgentsLive do
  use CuckodingWeb, :live_view
  alias Cuckoding.{Agents, Foundation}
  alias CuckodingWeb.Layouts
  import CuckodingWeb.Dialog
  alias Phoenix.LiveView.JS

  @impl true
  def mount(_, _, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Cuckoding.PubSub, "foundation")
      Process.send_after(self(), :catalog_tick, 30_000)
    end

    {:ok, socket |> assign(key: Ecto.UUID.generate(), error: nil, message: nil) |> load()}
  end

  @impl true
  def handle_event("disconnect", params, socket) do
    if params["key"] == socket.assigns.key and
         params["revision"] == to_string(socket.assigns.revision) and
         Enum.any?(socket.assigns.agents, fn {agent, _} -> agent.id == params["agent_id"] end) do
      result =
        Foundation.disconnect_agent(
          socket.assigns.key,
          socket.assigns.revision,
          true,
          params["agent_id"]
        )

      case result do
        {:ok, %{state: "pending"}} ->
          disconnected(
            socket,
            params,
            "Disconnect requested. Its roles are now unassigned; saved history is retained."
          )

        {:ok, %{state: "completed", kind: "disconnect_agent"}} ->
          disconnected(
            socket,
            params,
            "Disconnected locally and unassigned its roles. Provider sign-out was not attempted because the executable needs verification. The private profile is retained."
          )

        {:ok, %{result: "agent_in_battle"}} ->
          {:noreply,
           assign(socket, :error, "Stop the battle using this agent before disconnecting it.")}

        {:ok, %{result: "profile_busy"}} ->
          {:noreply,
           assign(
             socket,
             :error,
             "Finish or cancel the current setup action, then try Disconnect again."
           )}

        _ ->
          {:noreply,
           assign(
             socket,
             :error,
             "Connection setup changed or is busy. Open the agent to inspect it, then try again."
           )}
      end
    else
      {:noreply,
       assign(socket, :error, "This confirmation is out of date. Review the agent and try again.")}
    end
  end

  defp disconnected(socket, params, message) do
    {:noreply,
     socket
     |> assign(key: Ecto.UUID.generate(), error: nil, message: message)
     |> push_event("dialog-close", %{id: "disconnect-#{params["agent_id"]}"})
     |> load()}
  end

  @impl true
  def handle_info(:catalog_tick, socket) do
    Process.send_after(self(), :catalog_tick, 30_000)
    {:noreply, load(socket)}
  end

  def handle_info(:updated, socket), do: {:noreply, load(socket)}
  def handle_info(:session_expired, socket), do: {:noreply, redirect(socket, to: "/locked")}

  defp load(socket) do
    revision = Foundation.workspace().revision
    agents = Agents.list()

    assign(socket,
      agents: Enum.map(agents, &{&1, Foundation.saved_agent_models(&1.id)}),
      disconnected: MapSet.new(Enum.filter(agents, &Agents.disconnected?/1), & &1.id),
      revision: revision,
      busy: Foundation.pending?(),
      key:
        if(socket.assigns[:revision] && socket.assigns.revision != revision,
          do: Ecto.UUID.generate(),
          else: socket.assigns.key
        ),
      disconnects:
        Map.new(
          agents,
          &{&1.id, Foundation.last_probe(~w(logout_codex logout_cursor), &1.id)}
        )
    )
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.workspace active={:agents} title="Agents" flash={@flash}>
      <Layouts.journey current={1} />
      <section class="panel" aria-labelledby="agents-title">
        <p class="eyebrow">01 / YOUR AGENTS</p>
        <h2 id="agents-title">Build your roster.</h2>
        <p>Connect as many agents as you need. Give each role its own agent and model in Team.</p>
        <div class="team-actions">
          <.link navigate={~p"/agents/new"} class="button primary">Add agent</.link>
          <.link navigate={~p"/team"} class="button">Choose team roles</.link>
        </div>
        <p :if={@agents == []} class="fine-print">No agents yet. Add your first connection.</p>
        <p :if={@message} role="status">{@message}</p>
        <p :if={@error} role="alert" class="notice">{@error}</p>
        <ul class="agent-roster">
          <li :for={{agent, saved} <- @agents} id={"agent-#{agent.id}"}>
            <div>
              <strong>{agent.name}</strong>
              <p class="fine-print">
                {Agents.label(agent.kind)} · {cond do
                  MapSet.member?(@disconnected, agent.id) -> "Disconnected"
                  agent.connection["authorization"] in ~w(chatgpt cursor) -> "Signed in"
                  true -> "Connect account"
                end} · {if saved,
                  do: "#{length(saved.payload["model_ids"])} selected models",
                  else: "Setup unfinished"}
                <span :if={
                  Foundation.catalog_status(agent.connection) == "stale" &&
                    Foundation.reusable_catalog?(agent.connection)
                }> · saved models ready</span>
              </p>
              <p
                :if={
                  @disconnects[agent.id] &&
                    @disconnects[agent.id].state in ~w(pending running cancelling)
                }
                role="status"
              >
                Signing out… Open the agent for progress and Cancel.
              </p>
              <p
                :if={
                  @disconnects[agent.id] &&
                    @disconnects[agent.id].state in ~w(failed cancelled interrupted)
                }
                role="status"
              >
                Sign-out needs attention. Open the agent to inspect the result.
              </p>
            </div>
            <div class="team-actions">
              <.link
                navigate={~p"/agents/#{agent.id}"}
                class="button"
                aria-label={"Edit #{agent.name}"}
              >Edit</.link>
              <button
                type="button"
                class="button"
                aria-label={"Disconnect #{agent.name}"}
                disabled={@busy || MapSet.member?(@disconnected, agent.id)}
                phx-click={JS.dispatch("cc:open", to: "#disconnect-#{agent.id}")}
              >{if MapSet.member?(@disconnected, agent.id),
                do: "Disconnected",
                else: "Disconnect"}</button>
            </div>
            <.modal id={"disconnect-#{agent.id}"} title={"Disconnect #{agent.name}?"}>
              <p>
                Disconnect this saved connection and unassign it from every current team role. Other agents, role instructions and saved history stay intact.
              </p>
              <p>
                With a verified executable, this also signs out of its private profile. Otherwise, it disconnects locally and retains the profile without running the program.
              </p>
              <p>To use this agent again, reconnect it and choose its roles in Team.</p>
              <p :if={@error} role="alert" class="notice">{@error}</p>
              <form id={"disconnect-form-#{agent.id}"} phx-submit="disconnect">
                <input type="hidden" name="agent_id" value={agent.id} />
                <input type="hidden" name="key" value={@key} />
                <input type="hidden" name="revision" value={@revision} />
                <button class="button" disabled={@busy} phx-disable-with="Disconnecting…">Disconnect and unassign</button>
              </form>
            </.modal>
          </li>
        </ul>
      </section>
    </Layouts.workspace>
    """
  end
end
