defmodule BossWeb.TaskDependencies do
  use BossWeb, :html

  attr :snapshot, :map, required: true
  attr :project_id, :integer, required: true
  attr :revision, :integer, required: true

  def panel(assigns) do
    ~H"""
    <section
      id="task-dependencies"
      aria-labelledby="task-dependencies-heading"
      class={[
        "min-w-0",
        @snapshot.dependencies == [] && @snapshot.issues == [] && @snapshot.ready? && "sr-only",
        (@snapshot.dependencies != [] || @snapshot.issues != [] || !@snapshot.ready?) &&
          "rounded-lg border border-line bg-surface p-3 text-xs"
      ]}
    >
      <div class="flex flex-wrap items-center justify-between gap-2">
        <h3 id="task-dependencies-heading" class="font-semibold text-ink">Dependencies</h3>
        <span class="font-mono text-[11px] text-muted">
          task snapshot revision {@revision}
        </span>
      </div>

      <p
        id="task-dependencies-status"
        role="status"
        class={[
          "mt-1",
          if(@snapshot.ready?, do: "text-muted", else: "text-warning")
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

      <ul :if={@snapshot.dependencies != []} class="mt-2 space-y-1.5">
        <li
          :for={dependency <- @snapshot.dependencies}
          class="flex flex-wrap items-baseline justify-between gap-2 rounded border border-line bg-paper px-2.5 py-1.5"
        >
          <div class="flex min-w-0 flex-wrap items-baseline gap-2">
            <.link
              :if={dependency.task_id}
              patch={~p"/projects/#{@project_id}/tasks/#{dependency.task_id}"}
              class="break-words font-medium text-forest hover:underline"
            >{dependency.title || dependency.reference}</.link>
            <code class="break-all font-mono text-[11px] text-muted">{dependency.reference}</code>
          </div>
          <span class={[
            "font-mono text-[11px]",
            if(dependency.satisfied?, do: "text-forest", else: "text-warning")
          ]}>
            {dependency_status(dependency)}
          </span>
        </li>
      </ul>

      <ul
        :if={@snapshot.issues != []}
        id="task-dependency-issues"
        class="mt-2 list-inside list-disc space-y-1 break-words text-warning"
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
