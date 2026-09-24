defmodule CuckodingWeb.ModalComponents do
  @moduledoc """
  Shared LiveView dialogs with native modal focus and keyboard behavior.
  """

  use CuckodingWeb, :html

  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :on_cancel, :string, required: true
  attr :return_focus, :string, required: true
  slot :inner_block, required: true

  def modal(assigns) do
    ~H"""
    <dialog
      id={@id}
      phx-hook="Modal"
      phx-mounted={JS.ignore_attributes("open")}
      data-cancel={@on_cancel}
      data-return-focus={@return_focus}
      aria-labelledby={"#{@id}-heading"}
      class="m-auto max-h-[calc(100dvh-2rem)] w-[calc(100%-2rem)] max-w-2xl overflow-y-auto overscroll-contain rounded-2xl border border-slate-200 bg-white p-5 text-slate-950 shadow-xl backdrop:bg-slate-950/40 sm:p-6"
    >
      <header class="mb-4 flex items-start justify-between gap-4">
        <h2 id={"#{@id}-heading"} class="text-xl font-semibold">{@title}</h2>
        <button
          type="button"
          phx-click={@on_cancel}
          aria-label={"Close #{@title}"}
          class="min-h-11 shrink-0 rounded-md border border-slate-400 px-3 text-sm font-medium focus-visible:outline-2 focus-visible:outline-offset-2"
        >
          Cancel
        </button>
      </header>
      {render_slot(@inner_block)}
    </dialog>
    """
  end
end
