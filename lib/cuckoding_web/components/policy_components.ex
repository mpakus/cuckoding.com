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

  def host_runner_notice(assigns) do
    ~H"""
    <aside
      id="host-runner-notice"
      aria-labelledby="host-runner-heading"
      class="space-y-2 rounded-lg border border-amber-300 bg-amber-50 p-4 text-amber-950"
    >
      <h2 id="host-runner-heading" class="font-semibold">Host runner: not a sandbox</h2>
      <p class="text-sm">
        Worktrees prevent normal Git overlap, but they do not confine an arbitrary host process. Filesystem, network, CPU, and memory limits may be advisory.
      </p>
      <p class="text-sm">
        Before starting, review the runtime permission mode, allowed worktree, protected paths, network class, plugins, opaque secret references, budget, and expiry. Agent details separate enforced from unenforced grant fields.
      </p>
    </aside>
    """
  end
end
