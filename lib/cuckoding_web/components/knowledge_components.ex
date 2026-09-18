defmodule CuckodingWeb.KnowledgeComponents do
  @moduledoc "Navigation shared by the knowledge review and dashboard views."

  use CuckodingWeb, :html

  attr :current, :string, required: true

  def knowledge_nav(assigns) do
    ~H"""
    <nav aria-label="Knowledge views" class="flex flex-wrap gap-2">
      <.link
        navigate={~p"/knowledge"}
        aria-current={current(@current, "review")}
        class={link_class(@current == "review")}
      >Review</.link>
      <.link
        navigate={~p"/knowledge/growth"}
        aria-current={current(@current, "growth")}
        class={link_class(@current == "growth")}
      >Growth</.link>
      <.link
        navigate={~p"/knowledge/lineage"}
        aria-current={current(@current, "lineage")}
        class={link_class(@current == "lineage")}
      >Lineage and Usage</.link>
    </nav>
    """
  end

  defp current(value, value), do: "page"
  defp current(_current, _value), do: nil

  defp link_class(true),
    do:
      "inline-flex min-h-10 items-center rounded-md bg-slate-950 px-4 font-medium text-white focus-visible:outline-2 focus-visible:outline-offset-2"

  defp link_class(false),
    do:
      "inline-flex min-h-10 items-center rounded-md border border-slate-400 bg-white px-4 font-medium text-slate-950 focus-visible:outline-2 focus-visible:outline-offset-2"
end
