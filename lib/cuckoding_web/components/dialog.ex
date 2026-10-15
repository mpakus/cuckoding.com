defmodule CuckodingWeb.Dialog do
  @moduledoc false
  use Phoenix.Component
  alias Phoenix.LiveView.JS

  attr :id, :string, required: true
  attr :title, :string, required: true
  slot :inner_block, required: true

  def modal(assigns) do
    ~H"""
    <dialog
      id={@id}
      class="app-dialog"
      phx-hook="Dialog"
      phx-mounted={JS.ignore_attributes("open")}
      aria-labelledby={@id <> "-title"}
    >
      <header class="dialog-heading">
        <h2 id={@id <> "-title"} tabindex="-1" data-dialog-title>{@title}</h2>
        <button
          type="button"
          class="button icon-button"
          aria-label={"Close #{@title}"}
          phx-click={JS.dispatch("cc:close", to: "##{@id}")}
        >×</button>
      </header>
      {render_slot(@inner_block)}
    </dialog>
    """
  end
end
