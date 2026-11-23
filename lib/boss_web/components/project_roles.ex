defmodule BossWeb.ProjectRoles do
  use BossWeb, :live_component
  alias Boss.Projects.RoleBindings
  alias Phoenix.LiveView.JS

  @role_order ~w(analytic implementer reviewer)

  @impl true
  def mount(socket) do
    {:ok,
     assign(socket,
       project: nil,
       open: false,
       roles_map: %{},
       error: nil
     )}
  end

  @impl true
  def update(%{open: open}, socket) when is_boolean(open) do
    {:ok, assign(socket, open: open, error: nil)}
  end

  def update(%{refresh: true}, socket) do
    if socket.assigns.project do
      {:ok, assign(socket, roles_map: RoleBindings.for_project(socket.assigns.project.id))}
    else
      {:ok, socket}
    end
  end

  def update(assigns, socket) do
    project = Map.get(assigns, :project, socket.assigns.project)

    roles_map =
      if project,
        do: RoleBindings.for_project(project.id),
        else: %{}

    {:ok,
     socket
     |> assign(Map.take(assigns, [:id, :project]))
     |> assign(roles_map: roles_map)}
  end

  @impl true
  def handle_event("open", _, socket) do
    {:noreply, assign(socket, open: true, error: nil)}
  end

  def handle_event("close", _, socket) do
    {:noreply, assign(socket, open: false, error: nil)}
  end

  def handle_event("toggle", _, socket) do
    {:noreply, assign(socket, open: !socket.assigns.open, error: nil)}
  end

  def handle_event(
        "select_project_role",
        %{"role_kind" => kind, "choice" => choice},
        %{assigns: %{project: %{id: project_id}}} = socket
      )
      when kind in @role_order do
    case RoleBindings.select(project_id, kind, choice) do
      {:ok, _} ->
        send(self(), {:project_roles_changed, project_id})

        {:noreply,
         assign(socket,
           roles_map: RoleBindings.for_project(project_id),
           error: nil
         )}

      {:error, _} ->
        {:noreply, assign(socket, error: "Could not save project role binding.")}
    end
  end

  def handle_event(
        "toggle_pool_member",
        %{"choice" => choice},
        %{assigns: %{project: %{id: project_id}}} = socket
      ) do
    case RoleBindings.toggle_implementer_pool(project_id, choice) do
      {:ok, _} ->
        send(self(), {:project_roles_changed, project_id})

        {:noreply,
         assign(socket,
           roles_map: RoleBindings.for_project(project_id),
           error: nil
         )}

      {:error, :at_least_one_implementer} ->
        {:noreply, assign(socket, error: "Keep at least one Implementer enabled in the pool.")}

      {:error, _} ->
        {:noreply, assign(socket, error: "Could not update Implementer pool.")}
    end
  end

  def handle_event(
        "enable_all_implementers",
        _,
        %{assigns: %{project: %{id: project_id}}} = socket
      ) do
    case RoleBindings.enable_all_implementers(project_id) do
      {:ok, _} ->
        send(self(), {:project_roles_changed, project_id})

        {:noreply,
         assign(socket,
           roles_map: RoleBindings.for_project(project_id),
           error: nil
         )}

      {:error, _} ->
        {:noreply, assign(socket, error: "Could not enable all Implementers.")}
    end
  end

  def handle_event(_, _, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :role_order, @role_order)

    ~H"""
    <div id={@id} class="min-w-0">
      <button
        id="open-project-roles"
        type="button"
        phx-target={@myself}
        phx-click="open"
        aria-haspopup="dialog"
        aria-expanded={to_string(@open)}
        class="app-button-secondary max-w-full flex-wrap justify-start gap-1.5 px-3 py-2 text-left text-xs"
      >
        <span class="font-semibold text-ink">Roles &amp; models</span>
        <%= if analytic = @roles_map["analytic"] do %>
          <span
            class="max-w-44 truncate rounded border border-line bg-paper px-1.5 py-0.5 font-mono text-[11px] text-body"
            title={analytic.active.tag}
          >
            {analytic.active.tag}
          </span>
        <% end %>
        <%= if impl = @roles_map["implementer"] do %>
          <%= if length(impl.pool) > 1 do %>
            <span
              id="project-roles-trigger-pool"
              class="rounded bg-sage px-1.5 py-0.5 font-mono text-[11px] font-semibold text-forest"
              title={Enum.map_join(impl.pool, ", ", & &1.tag)}
            >
              {hd(impl.pool).tag} +{length(impl.pool) - 1} · {length(impl.pool)} parallel
            </span>
          <% else %>
            <span
              class="max-w-44 truncate rounded border border-line bg-paper px-1.5 py-0.5 font-mono text-[11px] text-body"
              title={impl.active.tag}
            >
              {impl.active.tag}
            </span>
          <% end %>
        <% end %>
        <%= if rev = @roles_map["reviewer"] do %>
          <span
            class="max-w-44 truncate rounded border border-line bg-paper px-1.5 py-0.5 font-mono text-[11px] text-body"
            title={rev.active.tag}
          >
            {rev.active.tag}
          </span>
        <% end %>
      </button>

      <dialog
        :if={@open}
        id="project-roles-dialog"
        phx-hook="DialogModal"
        phx-mounted={JS.ignore_attributes("open")}
        data-return-focus="open-project-roles"
        aria-labelledby="project-roles-heading"
        class="app-modal sm:max-w-3xl open:flex open:flex-col"
      >
        <div class="flex shrink-0 items-start justify-between gap-4 border-b border-line bg-surface px-5 py-4 sm:px-6">
          <div class="min-w-0">
            <p class="app-eyebrow">Project Agent · Model · Role bindings</p>
            <h2 id="project-roles-heading" class="mt-1 text-lg font-semibold text-ink">
              Roles &amp; models
            </h2>
            <p class="mt-1 text-xs text-muted">
              Analytic decomposes docs &amp; dispatches tasks across your enabled Implementer pool; Reviewer verifies against specs or refines &amp; returns to Backlog.
            </p>
          </div>
          <button
            id="close-project-roles"
            data-modal-close
            type="button"
            phx-target={@myself}
            phx-click="close"
            autofocus
            class="app-button-secondary shrink-0 px-3 py-2 text-xs"
          >
            Close
          </button>
        </div>

        <div class="min-h-0 flex-1 space-y-4 overflow-y-auto px-5 py-5 sm:px-6">
          <p
            :if={@error}
            id="project-roles-error"
            role="alert"
            class="rounded-sm border border-danger-line bg-danger-soft px-2.5 py-1.5 text-xs text-danger"
          >
            {@error}
          </p>

          <div class="grid gap-3 md:grid-cols-3">
            <%= for kind <- @role_order, entry = @roles_map[kind], not is_nil(entry) do %>
              <div class="rounded-sm border border-line bg-surface p-3">
                <form
                  id={"project-role-form-#{kind}"}
                  phx-target={@myself}
                  phx-change="select_project_role"
                >
                  <input type="hidden" name="role_kind" value={kind} />
                  <div class="flex items-center justify-between gap-2">
                    <label for={"project-role-#{kind}"} class="text-xs font-semibold text-ink">
                      {entry.name}
                      <span class="font-normal text-muted">· {role_short_hint(kind)}</span>
                    </label>
                    <%= if kind == "implementer" and length(entry.pool) > 1 do %>
                      <span
                        id="project-implementer-pool-badge"
                        class="rounded bg-sage px-1.5 py-0.5 font-mono text-[10px] font-semibold text-forest"
                      >
                        {length(entry.pool)} parallel
                      </span>
                    <% else %>
                      <span
                        class="truncate font-mono text-[10px] font-semibold text-forest"
                        title={entry.active.tag}
                      >
                        {entry.active.tag}
                      </span>
                    <% end %>
                  </div>

                  <select
                    id={"project-role-#{kind}"}
                    name="choice"
                    class="app-field mt-1.5 w-full px-2 py-1.5 text-xs"
                  >
                    <option
                      :for={choice <- entry.choices}
                      value={choice.choice_key}
                      selected={choice.choice_key == entry.active.choice_key}
                    >
                      {choice.tag} ({choice.agent_name} · {choice.model_name}{if choice.reasoning_effort,
                        do: " · #{choice.reasoning_effort}",
                        else: ""})
                    </option>
                  </select>
                </form>

                <div
                  :if={kind == "implementer" and length(entry.choices) > 1}
                  id="project-implementer-pool"
                  class="mt-2.5 border-t border-line pt-2.5"
                >
                  <div class="flex items-center justify-between gap-2">
                    <span class="text-[11px] font-medium text-muted">
                      Multi-Implementer Pool ({length(entry.pool)}/{length(entry.choices)} enabled)
                    </span>
                    <button
                      :if={length(entry.pool) < length(entry.choices)}
                      id="enable-all-implementers"
                      type="button"
                      phx-target={@myself}
                      phx-click="enable_all_implementers"
                      class="text-[11px] font-medium text-forest underline underline-offset-2"
                    >
                      Enable all
                    </button>
                  </div>
                  <div class="mt-1.5 flex flex-wrap gap-1.5">
                    <%= for choice <- entry.choices do %>
                      <% checked? = MapSet.member?(entry.pool_keys, choice.choice_key) %>
                      <button
                        type="button"
                        phx-target={@myself}
                        phx-click="toggle_pool_member"
                        phx-value-choice={choice.choice_key}
                        aria-pressed={to_string(checked?)}
                        class={[
                          "inline-flex items-center gap-1 rounded-sm border px-2 py-1 font-mono text-[10px] transition-colors",
                          if(checked?,
                            do: "border-forest bg-sage font-semibold text-forest",
                            else: "border-line bg-paper text-muted hover:border-control-line"
                          )
                        ]}
                      >
                        <span>{if checked?, do: "✓", else: "+"}</span>
                        <span>{choice.tag}</span>
                      </button>
                    <% end %>
                  </div>
                </div>
              </div>
            <% end %>
          </div>

          <div class="flex items-center justify-end border-t border-line pt-3">
            <.link
              navigate={~p"/agents"}
              class="text-xs font-medium text-forest underline underline-offset-4"
            >
              Configure agents &amp; roles →
            </.link>
          </div>
        </div>
      </dialog>
    </div>
    """
  end

  defp role_short_hint("analytic"), do: "Plans docs & dispatches"
  defp role_short_hint("implementer"), do: "Parallel coding pool"
  defp role_short_hint("reviewer"), do: "Spec check & rework loop"
  defp role_short_hint(_), do: ""
end
