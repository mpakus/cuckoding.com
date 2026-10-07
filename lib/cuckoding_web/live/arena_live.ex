defmodule CuckodingWeb.ArenaLive do
  use CuckodingWeb, :live_view
  alias Cuckoding.{Arenas, Command, Foundation, Repo}
  alias CuckodingWeb.Layouts

  @impl true
  def mount(_, _, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Cuckoding.PubSub, "foundation")
      Process.send_after(self(), :tick, 1_000)
    end

    {:ok,
     socket
     |> assign(
       choice: Arenas.selection(),
       name: "",
       confirmed: false,
       error: nil,
       message: nil,
       key: Ecto.UUID.generate()
     )
     |> refresh()}
  end

  @impl true
  def handle_event("choose", _, socket) do
    case Arenas.choose(Ecto.UUID.generate()) do
      {:ok, command} ->
        {:noreply,
         socket
         |> assign(choice: command, confirmed: false, error: nil, message: nil)
         |> refresh()}

      _ ->
        {:noreply, assign(socket, :error, message("unavailable"))}
    end
  end

  def handle_event("cancel", _, socket) do
    if socket.assigns.choice, do: Foundation.cancel_probe(socket.assigns.choice.id)
    {:noreply, refresh(socket)}
  end

  def handle_event("change", params, socket), do: {:noreply, input(socket, params)}

  def handle_event("register", params, socket) do
    socket = input(socket, params)

    result =
      if socket.assigns.choice && params["selection_id"] == socket.assigns.choice.id,
        do:
          Arenas.register(
            socket.assigns.key,
            socket.assigns.choice.id,
            socket.assigns.name,
            socket.assigns.confirmed
          ),
        else: {:error, "selection_required"}

    case result do
      {:ok, arena} ->
        {:noreply,
         socket
         |> assign(
           message: "#{arena.name} registered locally.",
           error: nil,
           confirmed: false,
           name: "",
           key: Ecto.UUID.generate()
         )
         |> refresh()}

      {:error, reason} ->
        {:noreply, assign(socket, key: Ecto.UUID.generate(), error: message(reason))}
    end
  end

  @impl true
  def handle_info(:session_expired, socket), do: {:noreply, redirect(socket, to: "/locked")}
  def handle_info(:updated, socket), do: {:noreply, refresh(socket)}

  def handle_info(:tick, socket) do
    Process.send_after(self(), :tick, 1_000)
    {:noreply, assign(socket, :now, DateTime.utc_now())}
  end

  defp refresh(socket) do
    choice = socket.assigns.choice
    choice = if choice, do: Repo.get!(Command, choice.id), else: Arenas.selection()
    arenas = Arenas.list()
    selected = choice && choice.state == "completed" && choice.result == "selected"

    assign(socket,
      arenas: arenas,
      choice: choice,
      busy: Foundation.pending?(),
      now: DateTime.utc_now(),
      preview: selected && not Enum.any?(arenas, &(&1.selection_id == choice.id)),
      inherited: if(selected, do: Arenas.team(choice))
    )
  end

  defp input(socket, %{"name" => name} = params)
       when is_binary(name) and byte_size(name) <= 320 do
    same_selection = socket.assigns.choice && params["selection_id"] == socket.assigns.choice.id

    assign(socket,
      name: name,
      confirmed: same_selection == true and params["confirmed"] == "true",
      message: nil
    )
  end

  defp input(socket, _),
    do: assign(socket, confirmed: false, error: message("invalid_registration"))

  defp active?(choice), do: choice && choice.state in ~w(pending running cancelling)
  defp git_label("absent"), do: "No .git entry · initialization requires separate consent"
  defp git_label(_), do: "Git metadata found · repository validation pending"

  defp message("setup_busy"),
    do: "Another setup operation is active. Finish or cancel it, then choose a folder."

  defp message("already_registered"), do: "This folder is already registered. Your draft is kept."

  defp message("folder_changed"),
    do: "The selected folder changed or is unavailable. Choose it again."

  defp message("invalid_folder"),
    do:
      "Choose an accessible project directory outside system, credential and Cuckoding data folders."

  defp message("invalid_registration"),
    do: "Enter a name (1–80 characters) and confirm the displayed folder and team."

  defp message("interrupted"), do: "Folder selection was interrupted. Choose again when ready."
  defp message("cancelled"), do: "Folder selection cancelled. No project files changed."

  defp message("timeout"),
    do: "Folder selection timed out after two minutes. Choose again when ready."

  defp message("cleanup_uncertain"),
    do: "Chooser cleanup could not be confirmed. Close the native dialog before choosing again."

  defp message(_),
    do:
      "Folder selection is unavailable. Open this workspace from the Cuckoding menu bar app and try again."

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.workspace active={:arenas} title="Arenas" flash={@flash}>
      <section class="panel" aria-labelledby="arena-title">
        <p class="eyebrow">03 / YOUR PROJECTS</p>
        <h2 id="arena-title">Give your team an Arena.</h2>
        <p>Choose a local folder, then register it with a saved team.</p>
        <p class="fine-print">
          Registration leaves files untouched. Create Tabulae and draft tasks after registration.
        </p>
        <p :if={@message} role="status" class="team-message">{@message}</p>
        <p :if={@error} role="alert" class="notice">{@error}</p>
        <div class="team-actions">
          <button type="button" class="button primary" phx-click="choose" disabled={@busy}>Choose folder…</button>
          <.link navigate={~p"/team"} class="text-link">Edit default team ↗</.link>
        </div>
        <div :if={active?(@choice)} class="notice" role="status">
          <p>
            Folder chooser · {@choice.state} · {max(0, DateTime.diff(@now, @choice.inserted_at))}s
          </p>
          <p class="fine-print">
            Owner: you · macOS native dialog · no agent or model · two-minute limit
          </p>
          <button
            type="button"
            class="button"
            phx-click="cancel"
            disabled={@choice.state == "cancelling"}
          >Cancel selection</button>
        </div>
        <p
          :if={@choice && @choice.state in ~w(failed rejected cancelled)}
          class="notice"
          role="status"
        >
          {message(@choice.result)}
        </p>
        <.form
          :if={@preview}
          for={%{}}
          id="arena-form"
          phx-change="change"
          phx-submit="register"
          class="role-fields"
        >
          <input type="hidden" name="selection_id" value={@choice.id} />
          <label for="arena-name">Arena name</label>
          <input
            id="arena-name"
            name="name"
            type="text"
            value={@name}
            maxlength="80"
            required
            placeholder="My project"
          />
          <p class="arena-path">{@choice.payload["folder"]["path"]}</p>
          <p class="fine-print">{git_label(@choice.payload["folder"]["git_entry"])}</p>
          <.team revision={@inherited} id="preview-team" />
          <label class="confirm-executable">
            <input type="checkbox" name="confirmed" value="true" checked={@confirmed} />
            Register this folder with team revision {@inherited.id}. This grants no agent access.
          </label>
          <button class="button primary" type="submit" phx-disable-with="Registering…">Register Arena</button>
        </.form>
      </section>
      <section class="panel" aria-labelledby="saved-arenas">
        <h2 id="saved-arenas">Registered Arenas · {length(@arenas)}</h2>
        <p :if={@arenas == []} class="subtle">
          Your first Arena starts with a folder. Empty folders and existing projects are welcome.
        </p>
        <article :for={arena <- @arenas} id={"arena-#{arena.id}"} class="team-role">
          <h3>{arena.name}</h3>
          <.link navigate={~p"/arenas/#{arena.id}"} class="button">Open Tabulae</.link>
          <p class="arena-path">{arena.path}</p>
          <p class="fine-print">{git_label(arena.git_entry)} · observed at registration</p>
          <.team revision={arena.team_revision} id={"arena-team-#{arena.id}"} />
          <p class="fine-print">
            Registered {Calendar.strftime(arena.inserted_at, "%Y-%m-%d %H:%M UTC")} · execution unavailable
          </p>
        </article>
      </section>
    </Layouts.workspace>
    """
  end

  attr :revision, :any, required: true
  attr :id, :string, required: true

  defp team(assigns) do
    ~H"""
    <details id={@id} class="activity" phx-mounted={Phoenix.LiveView.JS.ignore_attributes("open")}>
      <summary>Registration team · revision {@revision.id}</summary>
      <p class="fine-print">
        Frozen at folder selection. Open Tabulae to inspect or explicitly adopt a newer team for future boards. No execution grants.
      </p>
      <dl class="team-history">
        <div :for={role <- @revision.definition["roles"]}>
          <dt>{role["name"]}</dt>
          <dd>
            {if role["model"] == "",
              do: "Unassigned draft",
              else:
                "#{role["agent"]} · #{role["model"]} · availability checked before future execution"}
            <p>{role["instructions"]}</p>
          </dd>
        </div>
      </dl>
    </details>
    """
  end
end
