defmodule CuckodingWeb.TeamLive do
  use CuckodingWeb, :live_view
  alias Cuckoding.{Agents, Arena, Repo, Tabula, Tabulae, Team, TeamAssignments}
  alias CuckodingWeb.Layouts
  @form_fields ~w(name instructions agent model_id parallel_agent parallel_model_id)

  @impl true
  def mount(params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Cuckoding.PubSub, "foundation")
      Process.send_after(self(), :catalog_tick, 30_000)
    end

    case edit_scope(socket.assigns.live_action, params) do
      {:ok, scope} ->
        {:ok,
         socket
         |> assign(message: nil, return_board: nil, scope: scope, scope_error: false)
         |> load_saved()}

      :error ->
        {:ok,
         socket
         |> put_flash(:error, "This team scope is unavailable.")
         |> redirect(to: ~p"/arenas")}
    end
  end

  @impl true
  def handle_params(params, _, socket) do
    case edit_scope(socket.assigns.live_action, params) do
      {:ok, scope} when scope == socket.assigns.scope ->
        board = if match?(%Tabula{}, scope), do: scope, else: return_board(params)
        {:noreply, assign(socket, return_board: board, scope_error: false)}

      _ ->
        {:noreply, assign(socket, :scope_error, true)}
    end
  end

  defp edit_scope(:team, _), do: {:ok, nil}

  defp edit_scope(:arena_team, params) do
    with {:ok, id} <- Ecto.UUID.cast(params["arena_id"]),
         %Arena{} = arena <- Repo.get(Arena, id),
         do: {:ok, arena},
         else: (_ -> :error)
  end

  defp edit_scope(:tabula_team, params) do
    with {:ok, arena} <- Ecto.UUID.cast(params["arena_id"]),
         {:ok, board} <- Ecto.UUID.cast(params["id"]),
         %Tabula{} = board <- Tabulae.get(arena, board),
         do: {:ok, board},
         else: (_ -> :error)
  end

  defp return_board(params) do
    with {:ok, arena} <- Ecto.UUID.cast(params["arena"]),
         {:ok, tabula} <- Ecto.UUID.cast(params["tabula"]),
         do: Tabulae.get(arena, tabula),
         else: (_ -> nil)
  end

  defp board_path(board), do: ~p"/arenas/#{board.arena_id}/tabulae/#{board.id}"
  defp scope_path(nil), do: ~p"/team"
  defp scope_path(%Arena{id: id}), do: ~p"/arenas/#{id}/team"
  defp scope_path(board), do: ~p"/arenas/#{board.arena_id}/tabulae/#{board.id}/team"
  defp scope_team(nil), do: Team.current()
  defp scope_team(scope), do: TeamAssignments.assigned(scope)

  @impl true
  def handle_event("change", params, socket) do
    {:noreply, update_draft(socket, params)}
  end

  def handle_event("save", params, socket) do
    current_form =
      not socket.assigns.scope_error and
        (is_nil(socket.assigns.scope) or params["key"] == socket.assigns.key)

    # Save validates the submitted pair even if its preceding change event was lost.
    socket = update_draft(socket, params, false)

    result =
      cond do
        not current_form ->
          {:error, :stale_form}

        socket.assigns.input_valid ->
          Team.save(
            socket.assigns.key,
            socket.assigns.draft_revision,
            socket.assigns.roles,
            socket.assigns.confirm_removal,
            socket.assigns.scope
          )

        true ->
          {:error, :invalid_roles}
      end

    case result do
      {:ok, revision} ->
        {:noreply,
         socket |> load_saved() |> assign(:message, "Team saved · revision #{revision.id}.")}

      {:error, reason} ->
        {:noreply,
         socket |> assign(:key, Ecto.UUID.generate()) |> assign(:error, error_message(reason))}
    end
  end

  def handle_event("add", _, socket) do
    if length(socket.assigns.roles) < 12 do
      {:noreply,
       assign(socket,
         roles: socket.assigns.roles ++ [Team.custom_role()],
         dirty: true,
         message: nil
       )}
    else
      {:noreply, socket}
    end
  end

  def handle_event("remove", %{"id" => id}, socket) do
    if Team.required?(id) do
      {:noreply, socket}
    else
      {:noreply,
       assign(socket,
         roles: Enum.reject(socket.assigns.roles, &(&1["id"] == id)),
         dirty: true,
         confirm_removal: false,
         message: nil
       )}
    end
  end

  def handle_event("reload", _, socket) do
    if socket.assigns.dirty do
      {:noreply, assign(socket, :discard_pending, true)}
    else
      {:noreply, load_saved(socket)}
    end
  end

  def handle_event("discard", _, socket), do: {:noreply, load_saved(socket)}
  def handle_event("keep", _, socket), do: {:noreply, assign(socket, :discard_pending, false)}

  @impl true
  def handle_info(:session_expired, socket), do: {:noreply, redirect(socket, to: "/locked")}

  def handle_info(:catalog_tick, socket) do
    Process.send_after(self(), :catalog_tick, 30_000)
    {:noreply, assign(socket, :catalog, Team.catalog())}
  end

  def handle_info(:updated, socket) do
    if socket.assigns.dirty do
      {:noreply,
       assign(socket,
         latest: scope_team(socket.assigns.scope),
         busy: scope_busy?(socket.assigns.scope),
         catalog: Team.catalog(),
         agents: Agents.list(),
         history: Team.history(socket.assigns.scope)
       )}
    else
      {:noreply, load_saved(socket)}
    end
  end

  defp load_saved(socket) do
    team = scope_team(socket.assigns.scope)

    assign(socket,
      base: team,
      busy: scope_busy?(socket.assigns.scope),
      draft_revision: team.id,
      latest: team,
      roles: Team.editable(team),
      catalog: Team.catalog(),
      agents: Agents.list(),
      history: Team.history(socket.assigns.scope),
      key: Ecto.UUID.generate(),
      dirty: false,
      confirm_removal: false,
      error: nil,
      input_valid: true,
      discard_pending: false
    )
  end

  defp update_draft(socket, params, reset_models \\ true)

  defp update_draft(socket, %{"roles" => values} = params, reset_models) when is_map(values) do
    revision = params["base_revision"]

    if valid_fields?(values) and
         (is_nil(revision) or (is_binary(revision) and byte_size(revision) <= 16)) do
      merge_draft(socket, params, reset_models)
    else
      assign(socket, input_valid: false, error: error_message(:invalid_roles))
    end
  end

  defp update_draft(socket, _, _),
    do: assign(socket, input_valid: false, error: error_message(:invalid_roles))

  defp valid_fields?(values) do
    map_size(values) <= 12 and
      Enum.all?(values, fn {_, fields} ->
        is_map(fields) and map_size(fields) <= 12 and
          Enum.all?(fields, fn {key, value} ->
            form_field?(key) and is_binary(value) and
              byte_size(value) <= 8_000 and String.valid?(value)
          end)
      end)
  end

  defp form_field?("_unused_" <> field), do: field in @form_fields

  defp form_field?(field),
    do: field in @form_fields

  defp merge_draft(socket, %{"roles" => values} = params, reset_models) do
    revision =
      case Integer.parse(params["base_revision"] || "#{socket.assigns.draft_revision}") do
        {value, ""} when value > 0 -> value
        _ -> 0
      end

    roles =
      Enum.map(
        socket.assigns.roles,
        &merge_role(&1, Map.get(values, &1["id"], %{}), reset_models)
      )

    assign(socket,
      roles: roles,
      draft_revision: revision,
      dirty: roles != Team.editable(socket.assigns.base),
      confirm_removal: params["confirm_removal"] == "true",
      input_valid: true,
      message: nil
    )
  end

  defp merge_role(role, fields, reset_models) do
    updated = Map.merge(role, Map.take(fields, @form_fields))
    updated = if reset_models, do: reset_changed_models(role, updated), else: updated

    if not Map.has_key?(role, "parallel_agent") and updated["parallel_agent"] in [nil, ""] and
         updated["parallel_model_id"] in [nil, ""],
       do: Map.drop(updated, ~w(parallel_agent parallel_model_id)),
       else: updated
  end

  defp reset_changed_models(role, updated) do
    Enum.reduce(
      [{"agent", "model_id"}, {"parallel_agent", "parallel_model_id"}],
      updated,
      fn {agent, model}, draft ->
        if draft[agent] != role[agent], do: Map.put(draft, model, ""), else: draft
      end
    )
  end

  defp removed(roles, base) do
    Enum.reject(base.definition["roles"], fn old -> Enum.any?(roles, &(&1["id"] == old["id"])) end)
  end

  defp scope_busy?(nil), do: false
  defp scope_busy?(scope), do: TeamAssignments.busy?(scope)

  defp model_options(role, catalog) do
    selected = Map.get(catalog.agents, role["agent"], %{status: :connection_required})
    models = if selected.status == :available, do: selected.selectable_models, else: []

    if role["model_id"] != "" and not Enum.any?(models, &(&1["id"] == role["model_id"])) do
      [%{"id" => role["model_id"], "name" => role["model_id"] <> " · saved binding"} | models]
    else
      models
    end
  end

  defp status(role, base, catalog, additional? \\ false)
  defp status(%{"agent" => ""}, _, _, _), do: "Choose an agent and model"
  defp status(%{"model_id" => ""}, _, _, _), do: "Agent selected · choose a model"

  defp status(role, base, catalog, additional?) do
    old = Enum.find(base.definition["roles"], &(&1["id"] == role["id"]))
    old = if old && additional?, do: Team.additional(old), else: old

    role =
      if old && old["agent"] == role["agent"] && old["model_id"] == role["model_id"],
        do: Map.put(role, "model", old["model"]),
        else: role

    role |> Team.binding_status(catalog) |> status_label()
  end

  defp status_label(:unassigned), do: "Unassigned draft"
  defp status_label(:version_required), do: "Check agent version"
  defp status_label(:connection_required), do: "Refresh connection"
  defp status_label(:sign_in_required), do: "Sign in to agent"
  defp status_label(:catalog_stale), do: "Refresh model catalog"
  defp status_label(:model_missing), do: "Saved model missing from catalog"
  defp status_label(:model_changed), do: "Saved model changed · reassign explicitly"
  defp status_label(:check_passed), do: "Model check passed"
  defp status_label(:untested), do: "Catalog model · access untested"

  defp incomplete_roles(roles),
    do:
      Enum.filter(
        roles,
        &(Team.required?(&1["id"]) and (&1["agent"] == "" or &1["model_id"] == ""))
      )

  defp responsibility("speculator"), do: "Speculator · required"
  defp responsibility("implementor"), do: "Implementor · required"
  defp responsibility("secutor"), do: "Secutor · required"
  defp responsibility("summa_rudis"), do: "Summa Rudis · coordinator"
  defp responsibility(_), do: "Custom · read-only · optional board stage"

  defp error_message("stale_team"),
    do: "A newer team was saved. Your draft is kept here; inspect the revisions before reloading."

  defp error_message(:stale_form),
    do:
      "This form or its scope changed. Your draft is kept; review the current scope and submit again."

  defp error_message("planning_active"),
    do:
      "Finish or cancel this board's planning request before saving its team. Your draft is kept."

  defp error_message("scope_missing"), do: "This team scope is unavailable. Your draft is kept."

  defp error_message("removal_confirmation_required"),
    do: "Confirm removal of saved custom roles before saving."

  defp error_message("model_refresh_required"),
    do: "This new binding needs a current agent connection and model catalog. Your draft is kept."

  defp error_message("worker_connection_conflict"),
    do:
      "Choose different saved connections for the primary and additional worker. Your draft is kept."

  defp error_message(_),
    do:
      "Use unique role names (1–60 characters), instructions up to 2,000 characters, and valid agent/model choices. Additional workers need a different saved connection. Keep the four required roles and at most 12 roles total."

  attr :binding, :map, required: true
  attr :role_id, :string, required: true
  attr :prefix, :string, default: ""
  attr :agents, :list, required: true
  attr :catalog, :map, required: true

  defp binding_fields(assigns) do
    ~H"""
    <div class="role-binding">
      <div>
        <label for={"#{@prefix}agent-#{@role_id}"}>Agent</label>
        <select id={"#{@prefix}agent-#{@role_id}"} name={"roles[#{@role_id}][#{@prefix}agent]"}>
          <option value="" selected={@binding["agent"] == ""}>Choose agent</option>
          <option :for={agent <- @agents} value={agent.id} selected={@binding["agent"] == agent.id}>
            {agent.name} · {Agents.label(agent.kind)}
          </option>
        </select>
      </div>
      <div>
        <label for={"#{@prefix}model-#{@role_id}"}>Model</label>
        <select
          id={"#{@prefix}model-#{@role_id}"}
          name={"roles[#{@role_id}][#{@prefix}model_id]"}
          disabled={@binding["agent"] == ""}
        >
          <option value="" selected={@binding["model_id"] == ""}>Choose model</option>
          <option
            :for={model <- model_options(@binding, @catalog)}
            value={model["id"]}
            selected={@binding["model_id"] == model["id"]}
          >
            {model["name"] || model["id"]}{if model["hidden"], do: " · additional"}
          </option>
        </select>
      </div>
    </div>
    """
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.workspace active={:team} title="Team" flash={@flash}>
      <Layouts.journey current={2} arena_path={@return_board && board_path(@return_board)} />
      <section class="panel team-editor" aria-labelledby="team-title">
        <p class="eyebrow">
          02 / {cond do
            match?(%Arena{}, @scope) -> "ARENA TEAM"
            @scope -> "BOARD TEAM"
            true -> "YOUR SAVED TEAM"
          end}
        </p>
        <h2 id="team-title">Cast your roles.</h2>
        <p>
          Choose an agent and model for each role.
          <span :if={!@scope}>Save once, reuse across projects.</span>
        </p>
        <p :if={@scope} id="team-scope-context" class="fine-print">
          <strong>{if match?(%Arena{}, @scope),
            do: "New boards in #{@scope.name}",
            else: "Only #{@scope.name}"}.</strong>
          {if match?(%Arena{}, @scope),
            do: "Existing boards keep their team.",
            else: "Future planning and battles use this team after Save."} Your saved defaults and past work stay unchanged. Saving starts no agents.
        </p>
        <p :if={@scope_error} id="team-scope-error" role="alert" class="notice">
          This address points to a different team. Your draft is kept and cannot be saved here.
          <.link patch={scope_path(@scope)}>Return to this team's address</.link>
        </p>
        <p :if={@return_board && !@scope} id="team-board-context" class="fine-print">
          Updating your saved team for <strong>{@return_board.name}</strong>.
          Save, then review it on that board. Its current assignments stay in place until you confirm.
          <.link navigate={board_path(@return_board)} class="text-link">← Back to {@return_board.name}</.link>
        </p>
        <p class="fine-print">
          Speculator creates tasks, Implementor writes code, Secutor reviews and Summa Rudis coordinates.
          Task generation and execution can use the assigned Codex or Cursor connection.
        </p>
        <p :if={@message} role="status" class="team-message">{@message}</p>
        <p :if={@busy} role="status" class="notice">
          This board is creating tasks. Finish or cancel that request before saving its team.
          Your draft is kept here.
        </p>
        <div :if={incomplete_roles(@roles) != []} id="team-incomplete" role="status" class="notice">
          <p>
            Finish these required roles before Start: {Enum.map_join(
              incomplete_roles(@roles),
              ", ",
              & &1["name"]
            )}.
            You can save this draft, but it cannot run yet.
          </p>
        </div>
        <p :if={@error} id="team-error" role="alert" class="notice">{@error}</p>
        <p :if={@latest.id != @draft_revision} role="status" class="notice">
          Revision {@latest.id} is now saved. This editor still holds your draft from revision {@draft_revision}.
        </p>
        <.form
          for={%{}}
          id="team-form"
          phx-change="change"
          phx-submit="save"
          aria-describedby={@error && "team-error"}
        >
          <input type="hidden" name="base_revision" value={@draft_revision} />
          <input type="hidden" name="key" value={@key} />
          <div class="role-grid">
            <section
              :for={role <- @roles}
              id={"role-#{role["id"]}"}
              class="role-card"
              aria-labelledby={"role-heading-#{role["id"]}"}
            >
              <h3 id={"role-heading-#{role["id"]}"}>
                {if role["name"] == "", do: "New role", else: role["name"]}
              </h3>
              <p class="fine-print">{status(role, @base, @catalog)}</p>
              <div class="role-fields">
                <.binding_fields
                  binding={role}
                  role_id={role["id"]}
                  agents={@agents}
                  catalog={@catalog}
                />
                <details
                  :if={Team.required?(role["id"])}
                  id={"role-workers-#{role["id"]}"}
                  phx-mounted={Phoenix.LiveView.JS.ignore_attributes("open")}
                >
                  <summary>Additional worker (optional)</summary>
                  <p class="fine-print">
                    Choose a different saved connection to run this role on a second independent task. Both workers share these instructions. Leave it empty to share the primary connection.
                  </p>
                  <p :if={Team.additional(role)["agent"] != ""} class="fine-print">
                    {status(Team.additional(role), @base, @catalog, true)}
                  </p>
                  <.binding_fields
                    binding={Team.additional(role)}
                    role_id={role["id"]}
                    prefix="parallel_"
                    agents={@agents}
                    catalog={@catalog}
                  />
                </details>
                <details
                  id={"role-options-#{role["id"]}"}
                  open={role["name"] == ""}
                  phx-mounted={Phoenix.LiveView.JS.ignore_attributes("open")}
                >
                  <summary>Name & instructions</summary>
                  <p class="fine-print">{responsibility(role["id"])}</p>
                  <label for={"name-#{role["id"]}"}>Name</label>
                  <input
                    type="text"
                    id={"name-#{role["id"]}"}
                    name={"roles[#{role["id"]}][name]"}
                    value={role["name"]}
                    maxlength="60"
                    required
                  />
                  <label for={"instructions-#{role["id"]}"}>Instructions</label>
                  <textarea
                    id={"instructions-#{role["id"]}"}
                    name={"roles[#{role["id"]}][instructions]"}
                    rows="3"
                    maxlength="2000"
                  >{role["instructions"]}</textarea>
                </details>
                <button
                  :if={not Team.required?(role["id"])}
                  type="button"
                  class="button"
                  phx-click="remove"
                  phx-value-id={role["id"]}
                >Remove from draft</button>
              </div>
            </section>
          </div>
          <div :if={removed(@roles, @base) != []} class="notice">
            <p>
              Remove from this team: {Enum.map_join(removed(@roles, @base), ", ", & &1["name"])}. Previous revisions remain available.
            </p>
            <label class="confirm-executable"><input
              type="checkbox"
              name="confirm_removal"
              value="true"
              checked={@confirm_removal}
            />Confirm removal of these saved roles</label>
          </div>
          <div class="team-actions">
            <button
              type="submit"
              class="button primary"
              phx-disable-with="Saving…"
              disabled={not @dirty or @scope_error or @busy}
            >{if @scope, do: "Save team here", else: "Save team"}</button>
            <button type="button" class="button" phx-click="add" disabled={length(@roles) >= 12}>Add role</button>
            <button type="button" class="button" phx-click="reload">Reload saved</button>
            <.link
              :if={!@dirty}
              id="team-next"
              navigate={
                cond do
                  @return_board -> board_path(@return_board) <> "#board-team"
                  @scope -> ~p"/arenas/#{@scope.id}"
                  true -> ~p"/arenas"
                end
              }
              class={if @return_board, do: "button primary", else: "text-link"}
            >{cond do
              @scope -> "Back to #{@scope.name}"
              @return_board -> "Review team for #{@return_board.name}"
              true -> "Next: Choose Arena"
            end} ↗</.link>
            <span class="fine-print">{if @dirty, do: "Unsaved draft", else: "Saved locally"}</span>
          </div>
        </.form>
        <div :if={@discard_pending} class="notice" role="alert">
          <p>Discard your unsaved draft and load the latest saved team?</p>
          <button class="button" phx-click="keep">Keep editing</button>
          <button class="button" phx-click="discard">Discard draft and reload</button>
        </div>
        <details
          id="team-history"
          class="activity"
          phx-mounted={Phoenix.LiveView.JS.ignore_attributes("open")}
        >
          <summary>Recent saved revisions · latest five</summary>
          <details
            :for={revision <- @history}
            id={"team-revision-#{revision.id}"}
            phx-mounted={Phoenix.LiveView.JS.ignore_attributes("open")}
          >
            <summary>
              Revision {revision.id} · {Calendar.strftime(revision.inserted_at, "%Y-%m-%d %H:%M UTC")}
            </summary>
            <dl class="team-history">
              <div :for={role <- Team.bindings(revision.definition["roles"])}>
                <dt>{role["name"]} · {responsibility(role["id"])}</dt>
                <dd>
                  {if role["model"] == "",
                    do: "Unassigned draft",
                    else: "#{Agents.display(role["agent"])} · #{role["model"]}"}
                  <p>{role["instructions"]}</p>
                </dd>
              </div>
            </dl>
          </details>
        </details>
      </section>
    </Layouts.workspace>
    """
  end
end
