defmodule CuckodingWeb.RuntimeComponents do
  @moduledoc false
  use Phoenix.Component

  attr :runtime, :map, required: true

  def runtime_option(assigns) do
    ~H"""
    <div class="rounded-lg border border-amber-300 bg-amber-50 p-4">
      <label class="flex items-start gap-3 font-semibold text-slate-950">
        <input
          type="radio"
          name="runtime"
          value={@runtime.key}
          disabled={!@runtime.selectable?}
          aria-describedby={"runtime-#{@runtime.key}-warning"}
          class="mt-1 size-4"
        />
        <span>{@runtime.label}</span>
      </label>
      <p id={"runtime-#{@runtime.key}-warning"} class="mt-2 text-sm leading-6 text-amber-950">
        {@runtime.warning}
      </p>
    </div>
    """
  end
end
