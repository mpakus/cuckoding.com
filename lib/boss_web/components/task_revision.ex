defmodule BossWeb.TaskRevision do
  use BossWeb, :html

  attr :details, :map, required: true
  attr :request, :any, default: nil
  attr :available, :boolean, required: true
  attr :starting, :boolean, required: true

  def panel(assigns) do
    assigns =
      assign(
        assigns,
        :newer,
        assigns.details.selected_revision.number > assigns.details.pinned_revision.number
      )

    ~H"""
    <div id="task-revision-adoption" class="mt-3 space-y-3 text-sm">
      <%= if @request && (@newer || @request.locked) do %>
        <p id="adopt-revision-help" class="text-zinc-400">
          Using revision {@request.number} updates the task's title and dependencies and returns it to New.
          Previous runs and reviews stay in history; any previous approval is retired.
        </p>
        <p :if={@request.locked} id="adopt-revision-pending" role="status" class="text-amber-300">
          Request for revision {@request.number} is awaiting confirmation. Retry checks the same saved request.
        </p>
        <p :if={!@request.locked && !@details.adoption.available?} class="text-amber-300">
          {reason(@details.adoption.reason)}
        </p>
        <button
          id="adopt-revision"
          type="button"
          phx-click="adopt_revision"
          phx-value-command-id={@request.id}
          disabled={!@available}
          aria-describedby="adopt-revision-help"
          class="rounded-md border border-emerald-500 px-4 py-2 font-semibold text-emerald-300 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-emerald-400 disabled:opacity-50"
        >
          <%= cond do %>
            <% @starting -> %>
              Updating task…
            <% @request.locked -> %>
              Retry revision {@request.number}
            <% true -> %>
              Use revision {@request.number}
          <% end %>
        </button>
      <% else %>
        <p
          :if={@details.latest_revision.number > @details.pinned_revision.number}
          class="text-zinc-400"
        >
          Select a newer source revision to review and use it for this task.
        </p>
      <% end %>
      <p
        :if={@request && @request.error}
        id="adopt-revision-error"
        role="alert"
        class="text-amber-300"
      >
        {@request.error}
      </p>
    </div>
    """
  end

  def renew(request, details, project) do
    confirmed =
      request &&
        Enum.any?(details.events, fn event ->
          event.command_id == request.id && event.action == "adopt_revision" &&
            event.target_spec_revision_id == request.command.spec_revision_id &&
            event.version == request.command.expected_version + 1
        end)

    cond do
      request && request.locked && !confirmed ->
        request

      request && !confirmed && request.command.spec_revision_id == details.selected_revision.id &&
          request.command.expected_version == details.task.state_version ->
        request

      true ->
        id = Ecto.UUID.generate()

        %{
          id: id,
          number: details.selected_revision.number,
          locked: false,
          error: if(request && !confirmed, do: request.error),
          command: %{
            action: "adopt_revision",
            project_id: project,
            spec_revision_id: details.selected_revision.id,
            expected_version: details.task.state_version,
            command_id: id
          }
        }
    end
  end

  def number(details, id),
    do:
      Enum.find_value(Map.get(details, :revisions, []), fn revision ->
        if Map.get(revision, :id) == id, do: revision.number
      end) || "unavailable"

  def resolved?({:ok, _}), do: true

  def resolved?({:error, reason}),
    do:
      reason in [
        :not_found,
        :invalid_command,
        :stale_state,
        :idempotency_conflict,
        :task_unavailable,
        :busy,
        :integration_unresolved,
        :revision_unavailable,
        :source_unavailable
      ]

  def resolved?(_), do: false

  def error({:ok, _}), do: nil

  def error({:error, :stale_state}),
    do: "The task changed. Review its refreshed snapshot before trying again."

  def error({:error, :idempotency_conflict}),
    do: "This request belongs to different input. Refresh the task before trying again."

  def error({:error, reason}) when reason in [:not_found, :invalid_command],
    do: "This task or revision is unavailable. Open the task again."

  def error({:error, reason})
      when reason in [
             :task_unavailable,
             :busy,
             :integration_unresolved,
             :revision_unavailable,
             :source_unavailable
           ],
      do: reason(reason)

  def error(_),
    do:
      "The update outcome could not be confirmed. Retry the saved revision request before starting other work."

  defp reason(:task_unavailable), do: "This task cannot change its source in its current state."
  defp reason(:busy), do: "This task has active work or cleanup that needs attention."

  defp reason(:integration_unresolved),
    do: "An integration attempt needs reconciliation before this task can change its source."

  defp reason(:revision_unavailable), do: "Select a newer saved revision of this task."

  defp reason(:source_unavailable),
    do: "This saved source could not be validated. Import a corrected revision."

  defp reason(_), do: "This revision is not available for this task."
end
