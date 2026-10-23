defmodule CuckodingWeb.WorkflowComponent do
  @moduledoc false
  use CuckodingWeb, :live_component
  import CuckodingWeb.Dialog
  alias Cuckoding.{TeamAssignments, Workflows}

  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> assign(
       key: Ecto.UUID.generate(),
       scope: nil,
       names: nil,
       error: nil,
       notice: nil,
       dirty: false,
       stale: false,
       valid_input: true,
       discard_pending: false
     )
     |> CuckodingWeb.SessionAuth.guard_events()}
  end

  @impl true
  def update(assigns, socket) do
    scope = {assigns.board.arena_id, assigns.board.id}

    cond do
      is_nil(socket.assigns.scope) ->
        {:ok, socket |> assign(assigns) |> assign(:scope, scope) |> load_saved()}

      socket.assigns.scope == scope ->
        revision = Workflows.current(assigns.board)
        team = TeamAssignments.assigned(assigns.board)

        changed =
          revision.revision != socket.assigns.latest_revision or
            team.id != socket.assigns.latest_team_id

        {:ok,
         socket
         |> assign(assigns)
         |> assign(
           latest_revision: revision.revision,
           latest_team_id: team.id,
           stale:
             socket.assigns.stale or revision.revision != socket.assigns.base_revision or
               team.id != socket.assigns.team_id,
           key: if(changed, do: Ecto.UUID.generate(), else: socket.assigns.key),
           history:
             if(changed, do: Workflows.history(assigns.board.id), else: socket.assigns.history),
           blocker: Workflows.blocker(assigns.board)
         )}

      true ->
        {:ok, invalidate(socket)}
    end
  end

  defp load_saved(socket) do
    revision = Workflows.current(socket.assigns.board)

    names =
      Map.take(Workflows.labels(revision.definition), ~w(specs todo in_process review completed))

    steps = Workflows.editable_stages(revision.definition)
    team = TeamAssignments.assigned(socket.assigns.board)

    assign(socket,
      names: names,
      base_names: names,
      steps: steps,
      base_steps: steps,
      team_id: team.id,
      latest_team_id: team.id,
      custom_roles:
        Enum.reject(
          team.definition["roles"],
          &(&1["id"] in ~w(speculator implementor secutor summa_rudis))
        ),
      base_revision: revision.revision,
      latest_revision: revision.revision,
      history: Workflows.history(socket.assigns.board.id),
      blocker: Workflows.blocker(socket.assigns.board),
      key: Ecto.UUID.generate(),
      stale: false,
      dirty: false,
      valid_input: true,
      discard_pending: false,
      error: nil
    )
  end

  @impl true
  def handle_event("change", params, socket) do
    {:noreply,
     if(current_form?(params, socket.assigns),
       do: input(socket, params),
       else: invalidate(socket)
     )}
  end

  def handle_event("recover", params, socket) do
    socket =
      if same_scope?(params, socket.assigns), do: recover_input(socket, params), else: socket

    {:noreply, invalidate(socket)}
  end

  def handle_event("save", params, socket) do
    if current_form?(params, socket.assigns) and not socket.assigns.stale do
      socket = input(socket, params)
      a = socket.assigns
      {arena, board} = a.scope

      result =
        if a.valid_input,
          do:
            Workflows.configure_execution(
              a.key,
              arena,
              board,
              a.base_revision,
              a.team_id,
              a.names,
              a.steps
            ),
          else: {:error, "invalid_workflow"}

      socket =
        case result do
          {:ok, _} ->
            socket
            |> load_saved()
            |> assign(:notice, "Board workflow saved. No work was started.")

          {:error, reason} ->
            assign(socket,
              error: message(reason),
              key: Ecto.UUID.generate(),
              stale: reason in ["stale_workflow", "stale_team", :key_conflict]
            )
        end

      {:noreply, socket}
    else
      {:noreply, invalidate(socket)}
    end
  end

  def handle_event("reload", %{"key" => key}, socket) when key == socket.assigns.key do
    {:noreply,
     if(socket.assigns.dirty,
       do: assign(socket, :discard_pending, true),
       else: load_saved(socket)
     )}
  end

  def handle_event("discard", %{"key" => key}, socket)
      when key == socket.assigns.key and socket.assigns.discard_pending do
    {:noreply, socket |> load_saved() |> assign(:notice, nil)}
  end

  def handle_event("keep", _, socket), do: {:noreply, assign(socket, :discard_pending, false)}

  def handle_event("add_step", %{"key" => key}, socket) when key == socket.assigns.key do
    a = socket.assigns

    role =
      Enum.find(a.custom_roles, fn role -> Enum.all?(a.steps, &(&1["role"] != role["id"])) end)

    if role && length(a.steps) < 4 && not a.stale do
      step = %{
        "key" => "step_" <> Ecto.UUID.generate(),
        "name" => role["name"],
        "role" => role["id"],
        "access" => "read",
        "position" => "before"
      }

      {:noreply, assign(socket, steps: order_steps(a.steps ++ [step]), dirty: true, notice: nil)}
    else
      {:noreply,
       assign(
         socket,
         :error,
         "Add a different custom role in this board's Team first. Up to four stages are supported."
       )}
    end
  end

  def handle_event("move_step", %{"key" => key, "step" => id, "action" => action}, socket)
      when key == socket.assigns.key and action in ~w(up down remove) do
    a = socket.assigns
    index = Enum.find_index(a.steps, &(&1["key"] == id))
    steps = move_step(a.steps, index, action)

    {:noreply,
     assign(socket,
       steps: steps,
       dirty: steps != a.base_steps or a.names != a.base_names,
       notice: nil
     )}
  end

  def handle_event(_, _, socket), do: {:noreply, socket}

  defp order_steps(steps), do: Enum.sort_by(steps, &if(&1["position"] == "after", do: 1, else: 0))

  defp can_move?(steps, index, action) do
    position = Enum.at(steps, index)["position"]
    siblings = if action == "up", do: Enum.take(steps, index), else: Enum.drop(steps, index + 1)
    Enum.any?(siblings, &(&1["position"] == position))
  end

  defp move_step(steps, nil, _), do: steps
  defp move_step(steps, index, "remove"), do: List.delete_at(steps, index)

  defp move_step(steps, index, action) do
    if can_move?(steps, index, action) do
      step = Enum.at(steps, index)

      indices =
        for {sibling, i} <- Enum.with_index(steps), sibling["position"] == step["position"], do: i

      sibling = Enum.find_index(indices, &(&1 == index))
      target = Enum.at(indices, sibling + if(action == "up", do: -1, else: 1))
      steps |> List.replace_at(index, Enum.at(steps, target)) |> List.replace_at(target, step)
    else
      steps
    end
  end

  defp input(socket, %{"labels" => names} = params) when is_map(names) do
    unused = Enum.map(Map.keys(socket.assigns.base_names), &("_unused_" <> &1))
    names = Map.reject(names, fn {key, value} -> key in unused and value == "" end)

    steps = input_steps(params["steps"], socket.assigns.steps)

    if is_list(steps) and
         Enum.sort(Map.keys(names)) == Enum.sort(Map.keys(socket.assigns.base_names)) and
         Enum.all?(Map.values(names), &(is_binary(&1) and byte_size(&1) <= 160)) do
      assign(socket,
        names: names,
        steps: order_steps(steps),
        dirty: names != socket.assigns.base_names or steps != socket.assigns.base_steps,
        valid_input: true,
        error: nil,
        notice: nil,
        discard_pending: false
      )
    else
      assign(socket, valid_input: false, error: message("invalid_workflow"))
    end
  end

  defp input(socket, _),
    do: assign(socket, valid_input: false, error: message("invalid_workflow"))

  defp input_steps(nil, []), do: []

  defp input_steps(params, current) when is_map(params) do
    Enum.with_index(current)
    |> Enum.map(fn {step, index} -> input_step(params[to_string(index)], step) end)
    |> then(fn steps ->
      if Enum.all?(steps, &is_map/1) and map_size(params) == length(current), do: steps
    end)
  end

  defp input_steps(_, _), do: nil

  defp input_step(fields, step) when is_map(fields) do
    fields =
      Map.reject(fields, fn {key, value} ->
        key in ~w(_unused_access _unused_key _unused_name _unused_position _unused_role) and
          value == ""
      end)

    role = fields["role"]

    if fields["key"] == step["key"] and
         Enum.sort(Map.keys(fields)) == ~w(access key name position role) and
         is_binary(fields["name"]) and byte_size(fields["name"]) <= 160 and
         match?({:ok, ^role}, Ecto.UUID.cast(role)) and fields["access"] in ~w(read write) and
         fields["position"] in ~w(before after),
       do: fields
  end

  defp input_step(_, _), do: nil

  defp recover_input(socket, params) do
    steps = recovered_steps(params["steps"])
    if is_list(steps), do: socket |> assign(:steps, steps) |> input(params), else: socket
  end

  defp recovered_steps(nil), do: []

  defp recovered_steps(params) when is_map(params) and map_size(params) <= 4 do
    keys = Enum.take(~w(0 1 2 3), map_size(params))

    if Enum.sort(Map.keys(params)) == keys do
      steps = Enum.map(keys, &recovered_step(params[&1]))

      if Enum.all?(steps, &is_map/1) and length(Enum.uniq_by(steps, & &1["key"])) == length(steps),
        do: steps
    end
  end

  defp recovered_steps(_), do: nil

  defp recovered_step(%{"key" => key} = fields) do
    if Workflows.custom_key?(key),
      do:
        input_step(Map.merge(%{"access" => "read", "position" => "before"}, fields), %{
          "key" => key
        })
  end

  defp recovered_step(_), do: nil

  defp current_form?(params, a),
    do:
      same_scope?(params, a) and params["key"] == a.key and
        params["team_revision_id"] == to_string(a.team_id) and
        params["base_revision"] == to_string(a.base_revision)

  defp same_scope?(params, a),
    do: {params["arena_id"], params["tabula_id"]} == a.scope

  defp invalidate(socket),
    do:
      assign(socket,
        stale: true,
        key: Ecto.UUID.generate(),
        discard_pending: false,
        error:
          "This form changed or reconnected. Your draft is kept; reload saved workflow before saving."
      )

  defp message("planning_active"),
    do: "Finish or cancel this board's task planning before changing its columns."

  defp message("battle_active"),
    do: "Finish or Stop this board's battle before changing its columns."

  defp message("workflow_unchanged"), do: "This workflow is already saved."

  defp message("stale_team"),
    do:
      "This board's team changed or a selected role was removed. Reload the workflow and choose its roles again."

  defp message("invalid_workflow"),
    do:
      "Use five different names for the core columns, unique stage names (1–40 characters), and a different custom role for each stage."

  defp message(_), do: "The saved workflow changed. Your draft is kept; reload saved workflow."

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :columns, Workflows.default_definition()["columns"])

    ~H"""
    <div id={@id}>
      <.modal id="board-workflow" title="Board columns">
        <p class="fine-print">
          Name this board's columns and add optional roles around Implementor.
          Core roles and independent review stay in order. Saving starts no agent.
        </p>
        <p :if={@stale} role="status" class="notice">
          The saved workflow changed or the form reconnected. Your draft is kept.
        </p>
        <p :if={@blocker} id="workflow-busy" role="status">{message(@blocker)}</p>
        <p :if={@error} id="workflow-error" role="alert" class="notice">{@error}</p>
        <p :if={@notice} id="workflow-notice" role="status">{@notice}</p>
        <.form
          for={%{}}
          id="workflow-form"
          class="role-fields"
          phx-target={@myself}
          phx-change="change"
          phx-submit="save"
          phx-auto-recover="recover"
        >
          <input type="hidden" name="key" value={@key} />
          <input type="hidden" name="base_revision" value={@base_revision} />
          <input type="hidden" name="arena_id" value={elem(@scope, 0)} />
          <input type="hidden" name="tabula_id" value={elem(@scope, 1)} />
          <input type="hidden" name="team_revision_id" value={@team_id} />
          <details
            id="workflow-core-names"
            phx-mounted={Phoenix.LiveView.JS.ignore_attributes("open")}
          >
            <summary>Column names</summary>
            <div :for={column <- @columns} class="role-fields">
              <label for={"workflow-#{column["key"]}"}>{column["name"]} label</label>
              <input
                id={"workflow-#{column["key"]}"}
                type="text"
                name={"labels[#{column["key"]}]"}
                value={@names[column["key"]]}
                required
                maxlength="40"
              />
            </div>
          </details>
          <fieldset class="role-fields">
            <legend>Custom stages</legend>
            <p class="fine-print">
              Up to four roles run before or after Implementor, after Speculator and before independent review. Choose read access or explicitly allow file edits. No stage can run commands. Each stage uses your provider allowance after Start.
            </p>
            <article
              :for={{step, index} <- Enum.with_index(@steps)}
              id={"workflow-#{step["key"]}"}
              class="role-fields"
            >
              <input type="hidden" name={"steps[#{index}][key]"} value={step["key"]} />
              <label for={"step-name-#{step["key"]}"}>Stage name</label>
              <input
                id={"step-name-#{step["key"]}"}
                type="text"
                name={"steps[#{index}][name]"}
                value={step["name"]}
                maxlength="40"
                required
              />
              <label for={"step-role-#{step["key"]}"}>Role</label>
              <select id={"step-role-#{step["key"]}"} name={"steps[#{index}][role]"}>
                <option
                  :if={!Enum.any?(@custom_roles, &(&1["id"] == step["role"]))}
                  value={step["role"]}
                  selected
                >
                  Removed role · choose another
                </option>
                <option
                  :for={role <- @custom_roles}
                  value={role["id"]}
                  selected={role["id"] == step["role"]}
                >
                  {role["name"]}
                </option>
              </select>
              <label for={"step-access-#{step["key"]}"}>File access</label>
              <select id={"step-access-#{step["key"]}"} name={"steps[#{index}][access]"}>
                <option value="read" selected={step["access"] == "read"}>Read only</option>
                <option value="write" selected={step["access"] == "write"}>
                  Read and edit files
                </option>
              </select>
              <label for={"step-position-#{step["key"]}"}>Run</label>
              <select id={"step-position-#{step["key"]}"} name={"steps[#{index}][position]"}>
                <option value="before" selected={step["position"] == "before"}>
                  Before Implementor
                </option>
                <option value="after" selected={step["position"] == "after"}>
                  After Implementor
                </option>
              </select>
              <div class="team-actions">
                <button
                  :for={action <- ~w(up down remove)}
                  type="button"
                  class="button"
                  phx-target={@myself}
                  phx-click="move_step"
                  phx-value-key={@key}
                  phx-value-step={step["key"]}
                  phx-value-action={action}
                  disabled={
                    @stale or (action in ~w(up down) and not can_move?(@steps, index, action))
                  }
                  aria-label={"#{String.capitalize(action)} #{step["name"]}"}
                >{String.capitalize(action)}</button>
              </div>
            </article>
            <button
              type="button"
              class="button"
              phx-target={@myself}
              phx-click="add_step"
              phx-value-key={@key}
              disabled={length(@steps) >= min(4, length(@custom_roles)) or @stale}
            >+ Add stage</button>
            <.link navigate={"/arenas/#{elem(@scope, 0)}/tabulae/#{elem(@scope, 1)}/team"}>Edit this board's roles ↗</.link>
          </fieldset>
          <button
            class="button primary"
            disabled={@stale or not @dirty or not is_nil(@blocker)}
            phx-disable-with="Saving…"
          >Save workflow</button>
        </.form>
        <button
          type="button"
          class="button"
          phx-target={@myself}
          phx-click="reload"
          phx-value-key={@key}
        >Reload saved workflow</button>
        <div
          :if={@discard_pending}
          id="workflow-discard"
          role="group"
          aria-label="Discard unsaved workflow"
        >
          <p>Your unsaved workflow will be replaced with the saved version.</p>
          <button type="button" class="button" phx-target={@myself} phx-click="keep">Keep editing</button>
          <button
            type="button"
            class="button"
            phx-target={@myself}
            phx-click="discard"
            phx-value-key={@key}
          >Discard draft and reload</button>
        </div>
        <details
          :if={@history != []}
          id="workflow-history"
          phx-mounted={Phoenix.LiveView.JS.ignore_attributes("open")}
        >
          <summary>Workflow history</summary>
          <article :for={revision <- @history} id={"workflow-revision-#{revision.revision}"}>
            <p class="fine-print">
              {Calendar.strftime(revision.inserted_at, "%Y-%m-%d %H:%M UTC")} · version {revision.revision}
            </p>
            <p>{Enum.map_join(revision.definition["columns"], " → ", & &1["name"])}</p>
          </article>
        </details>
      </.modal>
    </div>
    """
  end
end
