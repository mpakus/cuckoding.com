defmodule BossWeb.TaskDependencies do
  use BossWeb, :html

  attr :snapshot, :map, required: true
  attr :project_id, :integer, required: true
  attr :revision, :integer, required: true

  def panel(assigns) do
    ~H"""
    <section id="task-dependencies" aria-labelledby="task-dependencies-heading">
      <h3 id="task-dependencies-heading" class="font-semibold">Dependencies</h3>
      <p class="mt-1 text-xs text-zinc-400">
        From task snapshot revision {@revision}. Viewing or importing another revision does not change them.
      </p>
      <p
        id="task-dependencies-status"
        role="status"
        class={[
          "mt-3 text-sm",
          if(@snapshot.ready?, do: "text-zinc-300", else: "text-amber-300")
        ]}
      >
        <%= cond do %>
          <% !@snapshot.ready? -> %>
            New runs wait until dependencies are Done and all dependency issues are resolved.
          <% @snapshot.dependencies == [] -> %>
            No dependencies.
          <% true -> %>
            All dependencies are Done.
        <% end %>
      </p>
      <ul :if={@snapshot.dependencies != []} class="mt-3 space-y-2 text-sm">
        <li
          :for={dependency <- @snapshot.dependencies}
          class="flex flex-wrap items-baseline gap-x-2 gap-y-1"
        >
          <.link
            :if={dependency.task_id}
            patch={~p"/projects/#{@project_id}/tasks/#{dependency.task_id}"}
            class="break-words text-emerald-400 underline underline-offset-4 focus-visible:outline-2 focus-visible:outline-emerald-400"
          >{dependency.title || dependency.reference}</.link>
          <code class="break-all text-xs text-zinc-400">{dependency.reference}</code>
          <span class={if dependency.satisfied?, do: "text-zinc-300", else: "text-amber-300"}>
            {dependency_status(dependency)}
          </span>
        </li>
      </ul>
      <ul
        :if={@snapshot.issues != []}
        id="task-dependency-issues"
        class="mt-3 list-inside list-disc space-y-1 break-words text-sm text-amber-300"
      >
        <li :for={issue <- @snapshot.issues}>{issue.message}</li>
      </ul>
    </section>
    """
  end

  defp dependency_status(%{satisfied?: true, missing: true}), do: "Done · source missing"
  defp dependency_status(%{satisfied?: true}), do: "Done"
  defp dependency_status(%{task_id: nil}), do: "Unknown dependency"
  defp dependency_status(%{missing: true}), do: "Source missing"

  defp dependency_status(%{state: state}) when is_binary(state),
    do: "Waiting · " <> String.capitalize(String.replace(state, "_", " "))

  defp dependency_status(_), do: "Waiting"
end
