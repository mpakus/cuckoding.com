defmodule CuckodingWeb.Layouts do
  use CuckodingWeb, :html
  embed_templates "layouts/*"

  attr :active, :atom, required: true
  attr :title, :string, required: true
  attr :flash, :map, required: true
  slot :inner_block, required: true

  def workspace(assigns) do
    ~H"""
    <div class="app-shell">
      <a class="skip-link" href="#main">Skip to content</a>
      <aside class="sidebar" aria-label="Workspace navigation">
        <.link navigate={~p"/"} class="brand" aria-label="Cuckoding home"><img
          src={~p"/favicon.svg"}
          class="brand-mark"
          width="43"
          height="43"
          alt=""
        /><span>Cuckoding</span></.link>
        <nav aria-label="Main">
          <.link
            navigate={~p"/"}
            class={["nav-link", @active == :home && "active"]}
            aria-current={if @active == :home, do: "page"}
          ><span aria-hidden="true">▦</span> Tabula Gladiatorum</.link>
          <.link
            navigate={~p"/arenas"}
            class={["nav-link", @active == :arenas && "active"]}
            aria-current={if @active == :arenas, do: "page"}
          >
            <span aria-hidden="true">◇</span> Arenas
          </.link>
          <.link
            navigate={~p"/agents"}
            class={["nav-link", @active == :agents && "active"]}
            aria-current={if @active == :agents, do: "page"}
          ><span aria-hidden="true">⌘</span> Agents</.link>
          <.link
            navigate={~p"/team"}
            class={["nav-link", @active == :team && "active"]}
            aria-current={if @active == :team, do: "page"}
          ><span aria-hidden="true">♧</span> Team</.link>
          <.link
            navigate={~p"/settings"}
            class={["nav-link", @active == :settings && "active"]}
            aria-current={if @active == :settings, do: "page"}
          ><span aria-hidden="true">⚙</span> Settings</.link>
        </nav>
        <div class="sidebar-foot">
          <span class="status-dot" aria-hidden="true"></span>
          Local workspace <small>Foundation preview · 0.1.0</small>
        </div>
      </aside>
      <main id="main" class="main">
        <header class="page-header">
          <p class="eyebrow">LOCAL AI ORCHESTRATION</p>
          <h1>{@title}</h1>
        </header>
        <div :if={@flash["error"]} role="alert" class="notice">{@flash["error"]}</div>

        {render_slot(@inner_block)}
        <footer class="main-foot">
          <span>Speculator → Implementor → Secutor</span><span>Coordinated by Summa Rudis</span>
        </footer>
      </main>
    </div>
    """
  end

  attr :current, :integer, required: true
  attr :arena_path, :string, default: nil

  def journey(assigns) do
    ~H"""
    <nav class="journey" aria-label="Setup journey">
      <ol id="setup-journey">
        <li
          :for={
            {{label, path}, index} <-
              Enum.with_index(
                [
                  {"Agents", ~p"/agents"},
                  {"Roles", ~p"/team"},
                  {"Arena & Tabula", ~p"/arenas"},
                  {"Create tasks", @arena_path},
                  {"Start", @arena_path}
                ],
                1
              )
          }
          aria-current={if index == @current, do: "step"}
        >
          <.link :if={path} navigate={path}><b>0{index}</b><span>{label}</span></.link>
          <span :if={!path}><b>0{index}</b><span>{label}</span></span>
        </li>
      </ol>
    </nav>
    """
  end

  attr :arena, :any, required: true

  def arena_link(assigns) do
    ~H"""
    <.link navigate={~p"/arenas/#{@arena.id}"} class="arena-link" id={"arena-#{@arena.id}"}>
      <span class="arena-symbol" aria-hidden="true">◇</span>
      <span><strong>{@arena.name}</strong><small class="arena-path">{@arena.path}</small></span>
      <span class="arena-open">Open Arena <span aria-hidden="true">↗</span></span>
    </.link>
    """
  end
end
