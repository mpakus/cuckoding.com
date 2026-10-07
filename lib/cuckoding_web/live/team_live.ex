defmodule CuckodingWeb.TeamLive do
  use CuckodingWeb, :live_view
  alias Cuckoding.Team
  alias CuckodingWeb.Layouts

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Cuckoding.PubSub, "foundation")
      Process.send_after(self(), :catalog_tick, 30_000)
    end

    {:ok, socket |> assign(:message, nil) |> load_saved()}
  end

  @impl true
  def handle_event("change", params, socket) do
    {:noreply, update_draft(socket, params)}
  end

  def handle_event("save", params, socket) do
    socket = update_draft(socket, params)

    result =
      if socket.assigns.input_valid,
        do:
          Team.save(
            socket.assigns.key,
            socket.assigns.draft_revision,
            socket.assigns.roles,
            socket.assigns.confirm_removal
          ),
        else: {:error, :invalid_roles}

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
       assign(socket, latest: Team.current(), catalog: Team.catalog(), history: Team.history())}
    else
      {:noreply, load_saved(socket)}
    end
  end

  defp load_saved(socket) do
    team = Team.current()

    assign(socket,
      base: team,
      draft_revision: team.id,
      latest: team,
      roles: Team.editable(team),
      catalog: Team.catalog(),
      history: Team.history(),
      key: Ecto.UUID.generate(),
      dirty: false,
      confirm_removal: false,
      error: nil,
      input_valid: true,
      discard_pending: false
    )
  end

  defp update_draft(socket, %{"roles" => values} = params) when is_map(values) do
    revision = params["base_revision"]

    if valid_fields?(values) and
         (is_nil(revision) or (is_binary(revision) and byte_size(revision) <= 16)) do
      merge_draft(socket, params)
    else
      assign(socket, input_valid: false, error: error_message(:invalid_roles))
    end
  end

  defp update_draft(socket, _),
    do: assign(socket, input_valid: false, error: error_message(:invalid_roles))

  defp valid_fields?(values) do
    map_size(values) <= 12 and
      Enum.all?(values, fn {_, fields} ->
        is_map(fields) and map_size(fields) <= 8 and
          Enum.all?(fields, fn {key, value} ->
            form_field?(key) and is_binary(value) and
              byte_size(value) <= 8_000 and String.valid?(value)
          end)
      end)
  end

  defp form_field?("_unused_" <> field), do: field in ~w(name instructions agent model_id)
  defp form_field?(field), do: field in ~w(name instructions agent model_id)

  defp merge_draft(socket, %{"roles" => values} = params) do
    revision =
      case Integer.parse(params["base_revision"] || "#{socket.assigns.draft_revision}") do
        {value, ""} when value > 0 -> value
        _ -> 0
      end

    roles =
      Enum.map(socket.assigns.roles, fn role ->
        fields = Map.get(values, role["id"], %{})

        fields =
          if is_map(fields), do: Map.take(fields, ~w(name instructions agent model_id)), else: %{}

        updated = Map.merge(role, fields)
        if updated["agent"] != role["agent"], do: Map.put(updated, "model_id", ""), else: updated
      end)

    assign(socket,
      roles: roles,
      draft_revision: revision,
      dirty: roles != Team.editable(socket.assigns.base),
      confirm_removal: params["confirm_removal"] == "true",
      input_valid: true,
      message: nil
    )
  end

  defp removed(roles, base) do
    Enum.reject(base.definition["roles"], fn old -> Enum.any?(roles, &(&1["id"] == old["id"])) end)
  end

  defp model_options(role, catalog) do
    models = if catalog.status == :available, do: catalog.models, else: []

    if role["model_id"] != "" and not Enum.any?(models, &(&1["id"] == role["model_id"])) do
      [%{"id" => role["model_id"], "name" => role["model_id"] <> " · saved binding"} | models]
    else
      models
    end
  end

  defp status(role, base, catalog) do
    old = Enum.find(base.definition["roles"], &(&1["id"] == role["id"]))

    role =
      if old && old["agent"] == role["agent"] && old["model_id"] == role["model_id"],
        do: Map.put(role, "model", old["model"]),
        else: role

    role |> Team.binding_status(catalog) |> status_label()
  end

  defp status_label(:unassigned), do: "Unassigned draft"
  defp status_label(:version_required), do: "Check Codex version"
  defp status_label(:connection_required), do: "Refresh connection"
  defp status_label(:sign_in_required), do: "Sign in to Codex"
  defp status_label(:catalog_stale), do: "Refresh model catalog"
  defp status_label(:model_missing), do: "Saved model missing from catalog"
  defp status_label(:model_changed), do: "Saved model changed · reassign explicitly"
  defp status_label(:check_passed), do: "Model check passed · execution unavailable"
  defp status_label(:untested), do: "Catalog model · access untested"

  defp responsibility("speculator"), do: "Speculator · required"
  defp responsibility("implementor"), do: "Implementor · required"
  defp responsibility("secutor"), do: "Secutor · required"
  defp responsibility("summa_rudis"), do: "Summa Rudis · coordinator"
  defp responsibility(_), do: "Custom · planning only · read-only"

  defp error_message("stale_team"),
    do: "A newer team was saved. Your draft is kept here; inspect the revisions before reloading."

  defp error_message("removal_confirmation_required"),
    do: "Confirm removal of saved custom roles before saving."

  defp error_message("model_refresh_required"),
    do: "This new binding needs a current Codex connection and model catalog. Your draft is kept."

  defp error_message(_),
    do:
      "Use unique role names (1–60 characters), instructions up to 2,000 characters, and valid agent/model choices. Keep the four required roles and at most 12 roles total."

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.workspace active={:team} title="Team" flash={@flash}>
      <section class="panel team-editor" aria-labelledby="team-title">
        <p class="eyebrow">02 / DEFAULT TEAM · REVISION {@base.id}</p>
        <h2 id="team-title">Cast your roles.</h2>
        <p>Give each role a name, instructions and a model. Unassigned drafts are welcome.</p>
        <p class="fine-print">
          Saving starts no agent. Execution slots and permissions are not enabled in this preview. Custom roles stay planning-only and read-only.
        </p>
        <p class="fine-print">
          <.link navigate={~p"/settings"} class="text-link">Manage agents and model checks ↗</.link>
        </p>
        <p :if={@message} role="status" class="team-message">{@message}</p>
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
          <details
            :for={role <- @roles}
            id={"role-#{role["id"]}"}
            class="team-role"
            open={role["name"] == ""}
            phx-mounted={Phoenix.LiveView.JS.ignore_attributes("open")}
          >
            <summary>
              <span>{if role["name"] == "", do: "New role", else: role["name"]}</span><small>{responsibility(
                role["id"]
              )} · {status(role, @base, @catalog)}</small>
            </summary>
            <div class="role-fields">
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
              <div class="role-binding">
                <div>
                  <label for={"agent-#{role["id"]}"}>Agent</label>
                  <select id={"agent-#{role["id"]}"} name={"roles[#{role["id"]}][agent]"}>
                    <option value="" selected={role["agent"] == ""}>Unassigned</option>
                    <option value="codex" selected={role["agent"] == "codex"}>
                      Codex · private connection
                    </option>
                  </select>
                </div>
                <div>
                  <label for={"model-#{role["id"]}"}>Model</label>
                  <select
                    id={"model-#{role["id"]}"}
                    name={"roles[#{role["id"]}][model_id]"}
                    disabled={role["agent"] == ""}
                  >
                    <option value="" selected={role["model_id"] == ""}>Unassigned</option>
                    <option
                      :for={model <- model_options(role, @catalog)}
                      value={model["id"]}
                      selected={role["model_id"] == model["id"]}
                    >
                      {model["name"] || model["id"]}
                    </option>
                  </select>
                </div>
              </div>
              <button
                :if={not Team.required?(role["id"])}
                type="button"
                class="button"
                phx-click="remove"
                phx-value-id={role["id"]}
              >Remove from draft</button>
            </div>
          </details>
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
              disabled={not @dirty}
            >Save team</button>
            <button type="button" class="button" phx-click="add" disabled={length(@roles) >= 12}>Add role</button>
            <button type="button" class="button" phx-click="reload">Reload saved</button>
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
              <div :for={role <- revision.definition["roles"]}>
                <dt>{role["name"]} · {responsibility(role["id"])}</dt>
                <dd>
                  {if role["model"] == "",
                    do: "Unassigned draft",
                    else: "#{role["agent"]} · #{role["model"]}"}
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
