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
          <p class="eyebrow">YOUR AGENTS. YOUR ARENA.</p>
          <h1>{@title}</h1>
          <p class="subtle">A quiet place to turn a plan into finished work.</p>
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
end
