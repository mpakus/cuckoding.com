defmodule CuckodingWeb.TeamAdoptionComponent do
  @moduledoc false
  use CuckodingWeb, :live_component
  alias Cuckoding.{Arena, Team, TeamAssignments}

  @impl true
  def mount(socket),
    do:
      {:ok,
       assign(socket,
         key: Ecto.UUID.generate(),
         expanded: false,
         error: nil,
         message: nil
       )
       |> CuckodingWeb.SessionAuth.guard_events()}

  @impl true
  def update(assigns, socket), do: {:ok, socket |> assign(assigns) |> refresh()}

  defp refresh(socket) do
    scope = socket.assigns.scope
    current = TeamAssignments.assigned(scope)
    candidate = Team.current()

    assign(socket,
      current: current,
      candidate: candidate,
      busy: TeamAssignments.busy?(scope),
      history: TeamAssignments.history(scope),
      changed: current.definition != candidate.definition,
      revisions: {current.id, candidate.id},
      key:
        if(socket.assigns[:revisions] == {current.id, candidate.id},
          do: socket.assigns.key,
          else: Ecto.UUID.generate()
        )
    )
  end

  @impl true
  def handle_event("adopt", params, socket) do
    a = socket.assigns
    arena? = match?(%Arena{}, a.scope)

    result =
      TeamAssignments.adopt(
        a.key,
        if(arena?, do: a.scope.id, else: a.scope.arena_id),
        if(arena?, do: nil, else: a.scope.id),
        a.current.id,
        a.candidate.id,
        current_form?(params, a)
      )

    {error, message} =
      case result do
        {:ok, _} ->
          {nil, "Saved team is now selected for future work."}

        {:error, "planning_active"} ->
          {"Finish or cancel this Tabula's planning request first.", nil}

        {:error, _} ->
          {"The team changed or this form is out of date. Review it and choose Use saved team again.",
           nil}
      end

    socket =
      if match?({:ok, _}, result) and not arena?,
        do: push_event(socket, "dialog-close", %{id: "board-team"}),
        else: socket

    {:noreply,
     socket
     |> assign(
       error: error,
       message: message,
       key: Ecto.UUID.generate()
     )
     |> refresh()}
  end

  def handle_event(_, _, socket), do: {:noreply, socket}

  defp current_form?(params, assigns) do
    params["key"] == assigns.key and
      params["expected"] == to_string(assigns.current.id) and
      params["target"] == to_string(assigns.candidate.id)
  end

  defp team_path(%Arena{}), do: ~p"/team"
  defp team_path(board), do: ~p"/team?#{[arena: board.arena_id, tabula: board.id]}"

  @impl true
  def render(assigns) do
    ~H"""
    <details
      id={@id}
      class="git-setup"
      open={@expanded}
      phx-mounted={Phoenix.LiveView.JS.ignore_attributes("open")}
    >
      <summary>
        {if match?(%Arena{}, @scope), do: "Team for new boards", else: "Board team"}
      </summary>
      <p class="fine-print">
        {if match?(%Arena{}, @scope),
          do: "New boards use this team. Existing boards keep their current assignments.",
          else:
            "This team creates tasks and works on future battles. Past work keeps its original assignments."} Changing the team starts no agent.
      </p>
      <.roster revision={@current} label="Current team" />
      <.link navigate={team_path(@scope)} class="text-link">Edit roles and models ↗</.link>
      <p :if={!@changed} role="status">
        This team matches your saved Team settings.
      </p>
      <div :if={@changed}>
        <.roster revision={@candidate} label="Your saved team" />
        <p class="fine-print">
          Use these roles, models and instructions for future work here. Past work keeps its original team.
        </p>
        <.form
          for={%{}}
          id={@id <> "-form"}
          phx-submit="adopt"
          phx-target={@myself}
        >
          <input type="hidden" name="key" value={@key} />
          <input type="hidden" name="expected" value={@current.id} />
          <input type="hidden" name="target" value={@candidate.id} />
          <button class="button" disabled={@busy} phx-disable-with="Saving…">Use saved team</button>
        </.form>
      </div>
      <p :if={@busy} role="status">
        Finish or cancel this Tabula's planning request before changing its team.
      </p>
      <p :if={@error} role="alert" class="notice">{@error}</p>
      <p :if={@message} role="status">{@message}</p>
      <details
        :if={@history != []}
        id={@id <> "-history"}
        phx-mounted={Phoenix.LiveView.JS.ignore_attributes("open")}
      >
        <summary>Team history</summary>
        <p class="fine-print">
          Each version is a saved set of roles, agents and models. History keeps past work traceable; you do not need to manage version numbers.
        </p>
        <article :for={entry <- @history}>
          <p class="fine-print">
            {Calendar.strftime(entry.inserted_at, "%Y-%m-%d %H:%M UTC")} · saved version {entry.team_revision_id}
          </p>
          <.roster revision={entry.team_revision} label="Adopted team" />
        </article>
      </details>
    </details>
    """
  end

  defp roster(assigns) do
    ~H"""
    <h3>{@label}</h3>
    <dl class="team-roster">
      <div :for={role <- @revision.definition["roles"]}>
        <dt>{role["name"]}</dt>
        <dd>{binding_label(role)}</dd>
      </div>
    </dl>
    <details class="fine-print">
      <summary>Role instructions</summary>
      <dl class="team-history">
        <div :for={role <- @revision.definition["roles"]}>
          <dt>{role["name"]}</dt>
          <dd>{instructions(role)}</dd>
        </div>
      </dl>
    </details>
    """
  end

  defp binding_label(%{"agent" => ""}), do: "Agent and model needed"

  defp binding_label(%{"model_id" => ""} = role),
    do: "#{Cuckoding.Agents.display(role["agent"])} · Model needed"

  defp binding_label(role), do: "#{Cuckoding.Agents.display(role["agent"])} · #{role["model_id"]}"
  defp instructions(%{"instructions" => ""}), do: "No extra instructions"
  defp instructions(role), do: role["instructions"]
end
