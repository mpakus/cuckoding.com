defmodule CuckodingWeb.Layouts do
  @moduledoc false
  use CuckodingWeb, :html

  embed_templates "layouts/*"

  attr :flash, :map, default: %{}
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
      <div id="flash-group" class="mb-6 space-y-3">
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
    """
  end
end
