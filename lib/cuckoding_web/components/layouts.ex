defmodule CuckodingWeb.Layouts do
  @moduledoc false
  use CuckodingWeb, :html

  embed_templates "layouts/*"

  attr :flash, :map, default: %{}
  attr :active, :string, default: nil
  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <header class="border-b border-slate-200 bg-white">
      <div class="mx-auto flex max-w-5xl flex-wrap items-center justify-between gap-3 px-4 py-3 sm:px-6">
        <a
          href={~p"/"}
          class="rounded text-lg font-semibold text-slate-950 focus-visible:outline-2 focus-visible:outline-offset-4"
        >
          Cuckoding
        </a>
        <nav aria-label="Main navigation" class="flex flex-wrap gap-2">
          <.link
            :for={
              {label, path, key} <- [
                {"Projects", ~p"/", "projects"},
                {"Agent activity", ~p"/agents", "agents"},
                {"Knowledge", ~p"/knowledge", "knowledge"}
              ]
            }
            navigate={path}
            aria-current={if @active == key, do: "page"}
            class={[
              "inline-flex min-h-11 items-center rounded-md px-3 text-sm font-medium hover:bg-slate-100 focus-visible:outline-2 focus-visible:outline-offset-2",
              @active == key && "bg-slate-100 text-slate-950 underline underline-offset-4"
            ]}
          >{label}</.link>
        </nav>
      </div>
    </header>
    <main id="main-content" class="mx-auto min-w-0 max-w-5xl px-4 py-6 sm:px-6 sm:py-8">
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
