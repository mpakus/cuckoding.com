defmodule CuckodingWeb.Layouts do
  @moduledoc false
  use CuckodingWeb, :html

  embed_templates "layouts/*"

  attr :flash, :map, default: %{}
  attr :active, :string, default: nil
  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <div class="workspace-shell">
      <header class="workspace-sidebar">
        <.link navigate={~p"/"} class="workspace-brand">
          <span class="brand-mark" aria-hidden="true">c<span>·</span></span>
          <span>Cuckoding<span class="brand-caption">Your local workspace</span></span>
        </.link>
        <p class="nav-caption">Workspace</p>
        <nav aria-label="Main navigation" class="workspace-nav">
          <.link
            :for={
              {label, path, key, icon} <- [
                {"Projects", ~p"/", "projects",
                 "M3 3h7v7H3z M14 3h7v7h-7z M3 14h7v7H3z M14 14h7v7h-7z"},
                {"Agents", ~p"/settings/agents", "agent_settings",
                 "M12 3v3 M9 3h6 M5 7h14v13H5z M8 12h1 M15 12h1 M9 16h6 M2 11v5 M22 11v5"},
                {"Agent activity", ~p"/agents", "agents", "M3 17h3l4-11 4 14 4-9h3"},
                {"Knowledge", ~p"/knowledge", "knowledge",
                 "M12 5v16 M12 5C9 3 5 3 2 4v15c4-1 7-1 10 2 3-3 6-3 10-2V4c-3-1-7-1-10 1"}
              ]
            }
            navigate={path}
            aria-current={if @active == key, do: "page"}
            class="workspace-nav-link"
          >
            <svg
              viewBox="0 0 24 24"
              fill="none"
              stroke="currentColor"
              stroke-width="1.5"
              stroke-linecap="round"
              stroke-linejoin="round"
              aria-hidden="true"
            ><path d={icon} /></svg>
            <span>{label}</span><span class="nav-arrow" aria-hidden="true">›</span>
          </.link>
        </nav>
        <aside class="workspace-knowledge" aria-label="Project knowledge">
          <img src={~p"/assets/images/knowledge-crystal.webp"} width="480" height="480" alt="" />
          <div>
            <p class="eyebrow">Built from experience</p>
            <p class="knowledge-title">Make every run count.</p>
            <p class="knowledge-description">
              Review what your agents learn. Keep the knowledge that matters.
            </p>
            <.link navigate={~p"/knowledge"} class="knowledge-link">Review knowledge
            <span aria-hidden="true">↗</span></.link>
          </div>
        </aside>
        <p class="workspace-footnote"><span aria-hidden="true">◇</span> Local-first. Human-guided.</p>
      </header>
      <div class="workspace-content">
        <div class="workspace-topbar" aria-hidden="true">
          <span>Workspace <span class="topbar-divider">/</span>
          <span class="text-slate-900">{case @active do
            "projects" -> "Projects"
            "agent_settings" -> "Agents"
            "agents" -> "Agent activity"
            "knowledge" -> "Knowledge"
            _ -> "Overview"
          end}</span></span>
          <span class="local-label"><span class="local-symbol">⌘</span> On your Mac</span>
        </div>
        <main id="main-content" class="workspace-main">
          <div id="flash-group" class="space-y-3 empty:hidden">
            <p
              :if={message = Phoenix.Flash.get(@flash, :info)}
              id="flash-info"
              role="status"
              aria-live="polite"
              class="rounded-md border border-emerald-300 bg-emerald-50 p-4 text-sm font-medium text-emerald-950"
            >
              {message}
            </p>
            <p
              :if={message = Phoenix.Flash.get(@flash, :error)}
              id="flash-error"
              role="alert"
              class="rounded-md border border-red-300 bg-red-50 p-4 text-sm font-medium text-red-950"
            >
              {message}
            </p>
          </div>
          {render_slot(@inner_block)}
        </main>
      </div>
    </div>
    """
  end
end
