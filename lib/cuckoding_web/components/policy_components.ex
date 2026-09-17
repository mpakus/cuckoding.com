defmodule CuckodingWeb.PolicyComponents do
  @moduledoc "Accessible policy classification labels."

  use CuckodingWeb, :html

  attr :classification, :atom, required: true, values: [:enforced, :advisory]

  def classification_badge(assigns) do
    ~H"""
    <span
      :if={@classification == :enforced}
      class="inline-flex rounded-full border border-emerald-300 bg-emerald-50 px-2 py-1 text-xs font-semibold text-emerald-950"
      aria-label="Enforced by Cuckoding"
    >
      Enforced
    </span>
    <span
      :if={@classification == :advisory}
      class="inline-flex rounded-full border border-amber-300 bg-amber-50 px-2 py-1 text-xs font-semibold text-amber-950"
      aria-label="Advisory only; not enforced by the host runner"
    >
      Advisory · not enforced
    </span>
    """
  end
end
