defmodule CuckodingWeb.Layouts do
  @moduledoc false
  use CuckodingWeb, :html

  embed_templates "layouts/*"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <header class="border-b border-slate-200 bg-white">
      <div class="mx-auto flex max-w-5xl items-center justify-between px-4 py-4 sm:px-6">
        <a
          href={~p"/"}
          class="rounded text-lg font-semibold text-slate-950 focus-visible:outline-2 focus-visible:outline-offset-4"
        >
          Cuckoding
        </a>
        <span class="text-sm text-slate-600">Local control plane</span>
      </div>
    </header>
    <main id="main-content" class="mx-auto max-w-5xl px-4 py-10 sm:px-6">
      {render_slot(@inner_block)}
    </main>
    """
  end
end
