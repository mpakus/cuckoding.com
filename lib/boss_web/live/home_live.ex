defmodule BossWeb.HomeLive do
  use BossWeb, :live_view

  @impl true
  def render(assigns) do
    ~H"""
    <p class="text-sm font-semibold tracking-widest text-emerald-400">BOSS · LOCAL</p>
    <h1 class="mt-4 text-3xl font-semibold">Your workspace starts here</h1>
    <p class="mt-4 text-lg text-zinc-300">
      The local foundation is running. Project import and agent runs are the next steps.
    </p>
    <p class="mt-8 border-t border-zinc-800 pt-6 text-sm text-zinc-400">
      Closing this tab keeps BOSS running. Stop the server in your terminal when finished.
    </p>
    """
  end
end
