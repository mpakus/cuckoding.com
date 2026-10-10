defmodule CuckodingWeb.AgentsLive do
  use CuckodingWeb, :live_view
  alias Cuckoding.{Agents, Foundation}
  alias CuckodingWeb.Layouts

  @impl true
  def mount(_, _, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Cuckoding.PubSub, "foundation")
      Process.send_after(self(), :catalog_tick, 30_000)
    end

    {:ok, load(socket)}
  end

  @impl true
  def handle_info(:catalog_tick, socket) do
    Process.send_after(self(), :catalog_tick, 30_000)
    {:noreply, load(socket)}
  end

  def handle_info(:updated, socket), do: {:noreply, load(socket)}
  def handle_info(:session_expired, socket), do: {:noreply, redirect(socket, to: "/locked")}

  defp load(socket) do
    assign(socket, agents: Enum.map(Agents.list(), &{&1, Foundation.saved_agent_models(&1.id)}))
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.workspace active={:agents} title="Agents" flash={@flash}>
      <section class="panel" aria-labelledby="agents-title">
        <p class="eyebrow">01 / YOUR AGENTS</p>
        <h2 id="agents-title">Build your roster.</h2>
        <p>Connect as many agents as you need. Give each role its own agent and model in Team.</p>
        <div class="team-actions">
          <.link navigate={~p"/agents/new"} class="button primary">Add agent</.link>
          <.link navigate={~p"/team"} class="button">Choose team roles</.link>
        </div>
        <p :if={@agents == []} class="fine-print">No agents yet. Add your first connection.</p>
        <ul class="agent-roster">
          <li :for={{agent, saved} <- @agents} id={"agent-#{agent.id}"}>
            <div>
              <strong>{agent.name}</strong>
              <p class="fine-print">
                {Agents.label(agent.kind)} · {if agent.connection["authorization"] in ~w(chatgpt cursor),
                  do: "Signed in",
                  else: "Connect account"} · {if saved,
                  do: "#{length(saved.payload["model_ids"])} selected models",
                  else: "Setup unfinished"}
                <span :if={agent.connection["models"]}> · catalog {Foundation.catalog_status(
                  agent.connection
                )}</span>
              </p>
            </div>
            <.link
              navigate={~p"/agents/#{agent.id}"}
              class="button"
              aria-label={"Edit #{agent.name}"}
            >Edit</.link>
          </li>
        </ul>
      </section>
    </Layouts.workspace>
    """
  end
end
