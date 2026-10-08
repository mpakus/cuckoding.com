defmodule CuckodingWeb.ProjectChecksLive do
  use CuckodingWeb, :live_view
  alias Cuckoding.{ProjectChecks, Tabulae}
  alias CuckodingWeb.Layouts

  @fields ~w(id name executable argument_lines directory timeout_seconds)

  @impl true
  def mount(%{"arena_id" => id}, _, socket) do
    case Tabulae.arena(id) do
      nil ->
        {:ok, redirect(socket, to: "/arenas")}

      arena ->
        if connected?(socket), do: Phoenix.PubSub.subscribe(Cuckoding.PubSub, "foundation")
        {:ok, socket |> assign(arena: arena, message: nil) |> load_saved()}
    end
  end

  defp load_saved(socket) do
    base = ProjectChecks.current(socket.assigns.arena.id)

    socket
    |> assign(
      base: base,
      checks: Enum.map(base.definition["checks"], &draft/1),
      key: Ecto.UUID.generate(),
      dirty: false,
      matches: true,
      input_valid: true,
      preview: nil,
      confirmed: false,
      error: nil,
      discard_pending: false
    )
    |> refresh()
  end

  defp draft(check) do
    check
    |> Map.put("argument_lines", Enum.join(check["arguments"], "\n"))
    |> Map.put("timeout_seconds", to_string(check["timeout_seconds"]))
    |> Map.delete("arguments")
  end

  defp refresh(socket) do
    current = ProjectChecks.current(socket.assigns.arena.id)

    assign(socket,
      latest: current,
      history: ProjectChecks.history(socket.assigns.arena.id),
      confirmed: socket.assigns.confirmed and current.revision == socket.assigns.base.revision
    )
  end

  @impl true
  def handle_event("change", params, socket), do: {:noreply, input(socket, params)}

  def handle_event("add", _, socket) do
    if length(socket.assigns.checks) < 8 do
      check = %{
        "id" => Ecto.UUID.generate(),
        "name" => "",
        "executable" => "",
        "argument_lines" => "",
        "directory" => ".",
        "timeout_seconds" => "300"
      }

      {:noreply, changed(socket, socket.assigns.checks ++ [check])}
    else
      {:noreply, socket}
    end
  end

  def handle_event("remove", %{"id" => id}, socket),
    do: {:noreply, changed(socket, Enum.reject(socket.assigns.checks, &(&1["id"] == id)))}

  def handle_event("review", params, socket) do
    socket = socket |> input(params) |> refresh()
    a = socket.assigns

    result =
      cond do
        not a.matches or a.base.revision != a.latest.revision -> {:error, "stale_checks"}
        not a.input_valid -> {:error, "invalid_checks"}
        true -> ProjectChecks.preview(Enum.map(a.checks, &declaration/1))
      end

    case result do
      {:ok, definition} -> {:noreply, assign(socket, preview: definition, error: nil)}
      {:error, reason} -> {:noreply, assign(socket, error: message(reason))}
    end
  end

  def handle_event("confirm", params, socket), do: {:noreply, confirm(socket, params)}

  def handle_event("save", params, socket) do
    socket = confirm(socket, params)
    a = socket.assigns

    result =
      if a.preview && a.matches do
        ProjectChecks.save(a.key, a.arena.id, a.base.revision, a.preview["checks"], a.confirmed)
      else
        {:error, "confirmation_required"}
      end

    case result do
      {:ok, revision} ->
        {:noreply,
         socket
         |> load_saved()
         |> assign(
           :message,
           "Project checks saved · revision #{revision.revision}. Nothing was run."
         )}

      {:error, reason} ->
        {:noreply,
         assign(socket, confirmed: false, key: Ecto.UUID.generate(), error: message(reason))}
    end
  end

  def handle_event("reload", _, socket) do
    if socket.assigns.dirty,
      do: {:noreply, assign(socket, :discard_pending, true)},
      else: {:noreply, load_saved(socket)}
  end

  def handle_event("discard", _, socket), do: {:noreply, load_saved(socket)}
  def handle_event("keep", _, socket), do: {:noreply, assign(socket, :discard_pending, false)}
  def handle_event(_, _, socket), do: {:noreply, socket}

  @impl true
  def handle_info(:updated, socket), do: {:noreply, refresh(socket)}
  def handle_info(:session_expired, socket), do: {:noreply, redirect(socket, to: "/locked")}

  defp changed(socket, checks) do
    assign(socket, checks: checks, dirty: true, preview: nil, confirmed: false, message: nil)
  end

  defp input(socket, params) do
    values = Map.get(params, "checks", %{})

    if valid_fields?(values) do
      checks =
        values
        |> Enum.sort_by(fn {index, _} -> index end)
        |> Enum.map(fn {_, fields} -> Map.take(fields, @fields) end)

      matches =
        socket.assigns.matches and params["arena_id"] == socket.assigns.arena.id and
          params["base_revision"] == to_string(socket.assigns.base.revision)

      socket |> changed(checks) |> assign(matches: matches, input_valid: true)
    else
      assign(socket,
        input_valid: false,
        preview: nil,
        confirmed: false,
        error: message("invalid_checks")
      )
    end
  end

  defp valid_fields?(values) when is_map(values) and map_size(values) <= 8 do
    Enum.all?(values, fn {index, fields} ->
      index in ~w(0 1 2 3 4 5 6 7) and is_map(fields) and
        Enum.sort(Map.keys(Map.take(fields, @fields))) == Enum.sort(@fields) and
        Enum.all?(fields, fn {key, value} ->
          String.replace_prefix(key, "_unused_", "") in @fields and
            is_binary(value) and byte_size(value) <= 4_500 and String.valid?(value)
        end)
    end)
  end

  defp valid_fields?(_), do: false

  defp declaration(check) do
    timeout =
      case Integer.parse(check["timeout_seconds"]) do
        {value, ""} -> value
        _ -> nil
      end

    lines = String.replace(check["argument_lines"], "\r\n", "\n")

    check
    |> Map.delete("argument_lines")
    |> Map.put("arguments", if(lines == "", do: [], else: String.split(lines, "\n")))
    |> Map.put("timeout_seconds", timeout)
  end

  defp confirm(socket, params) do
    socket = refresh(socket)
    a = socket.assigns

    confirmed =
      a.preview != nil and a.matches and a.base.revision == a.latest.revision and
        params["confirmed"] == "true" and params["digest"] == ProjectChecks.digest(a.preview)

    assign(socket, :confirmed, confirmed)
  end

  defp message("stale_checks"),
    do:
      "A newer revision or a different form was loaded. Your draft is kept; inspect saved checks before reloading."

  defp message("confirmation_required"), do: "Review the exact checks and confirm before saving."
  defp message("checks_unchanged"), do: "These checks are already saved."

  defp message(_),
    do:
      "Use up to eight unique names (1–60 characters), executable names without paths or RTK, up to 16 literal arguments (256 bytes each), a relative directory without traversal, and a timeout of 1–1,800 seconds. Control characters are not allowed."

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.workspace active={:arenas} title={@arena.name} flash={@flash}>
      <section class="panel" aria-labelledby="checks-title">
        <p class="eyebrow">PROJECT CHECKS · REVISION {@base.revision}</p>
        <h2 id="checks-title">Define how to verify the work.</h2>
        <p>Save named checks once for this Arena. Future battles will use an exact saved revision.</p>
        <p class="fine-print">
          Saving runs nothing and grants no access. Commands may run project code; execution, worktree permissions and executable verification are not available yet. Keep credentials out of arguments.
        </p>
        <.link navigate={~p"/arenas/#{@arena.id}"} class="text-link">Back to Arena ↗</.link>
        <p :if={@message} role="status">{@message}</p>
        <p :if={@error} id="checks-error" role="alert" class="notice">{@error}</p>
        <p :if={@latest.revision != @base.revision || !@matches} role="status" class="notice">
          Saved revision {@latest.revision} is current. Reload before reviewing this draft.
        </p>
        <.form for={%{}} id="checks-form" phx-change="change" phx-submit="review">
          <input type="hidden" name="arena_id" value={@arena.id} />
          <input type="hidden" name="base_revision" value={@base.revision} />
          <p :if={@checks == []} class="subtle">
            No checks in this draft. Add the command you normally use to test this project.
          </p>
          <details
            :for={{check, index} <- Enum.with_index(@checks)}
            id={"check-#{check["id"]}"}
            class="team-role"
            open={check["name"] == ""}
            phx-mounted={Phoenix.LiveView.JS.ignore_attributes("open")}
          >
            <summary>{if check["name"] == "", do: "New check", else: check["name"]}</summary>
            <input type="hidden" name={"checks[#{index}][id]"} value={check["id"]} />
            <div class="role-fields">
              <label for={"check-name-#{check["id"]}"}>Check name</label>
              <input
                id={"check-name-#{check["id"]}"}
                name={"checks[#{index}][name]"}
                value={check["name"]}
                maxlength="60"
                required
              />
              <label for={"check-executable-#{check["id"]}"}>Executable name</label>
              <input
                id={"check-executable-#{check["id"]}"}
                name={"checks[#{index}][executable]"}
                value={check["executable"]}
                placeholder="mix"
                maxlength="80"
                required
              />
              <label for={"check-arguments-#{check["id"]}"}>Arguments · one per line</label>
              <textarea
                id={"check-arguments-#{check["id"]}"}
                name={"checks[#{index}][argument_lines]"}
                rows="3"
                maxlength="4112"
                placeholder="test"
              >{check["argument_lines"]}</textarea>
              <p class="fine-print">
                Each line is one nonempty literal argument. Spaces and quotes are preserved; no shell splitting or expansion. Leave the field blank for no arguments. Enter the underlying command without RTK.
              </p>
              <label for={"check-directory-#{check["id"]}"}>Directory within the future worktree</label>
              <input
                id={"check-directory-#{check["id"]}"}
                name={"checks[#{index}][directory]"}
                value={check["directory"]}
                maxlength="240"
                required
              />
              <label for={"check-timeout-#{check["id"]}"}>Timeout in seconds</label>
              <input
                id={"check-timeout-#{check["id"]}"}
                type="number"
                name={"checks[#{index}][timeout_seconds]"}
                value={check["timeout_seconds"]}
                min="1"
                max="1800"
                required
              />
              <button type="button" class="button" phx-click="remove" phx-value-id={check["id"]}>Remove from draft</button>
            </div>
          </details>
          <div class="team-actions">
            <button type="submit" class="button primary" disabled={!@dirty}>Review changes</button>
            <button type="button" class="button" phx-click="add" disabled={length(@checks) >= 8}>Add check</button>
            <button type="button" class="button" phx-click="reload">Reload saved checks</button>
          </div>
        </.form>
        <div :if={@discard_pending} class="notice" role="alert">
          <p>Discard your unsaved checks and load the latest saved revision?</p>
          <button class="button" phx-click="keep">Keep editing</button>
          <button class="button" phx-click="discard">Discard draft and reload</button>
        </div>
        <div :if={@preview} id="checks-preview" class="notice">
          <h3>Proposed revision {@base.revision + 1} · exact checks</h3>
          <p>
            This replaces all {@base.definition["checks"] |> length()} checks in revision {@base.revision}. Earlier revisions remain available.
          </p>
          <.declarations checks={@preview["checks"]} />
          <.form for={%{}} id="checks-confirm" phx-change="confirm" phx-submit="save">
            <input type="hidden" name="digest" value={ProjectChecks.digest(@preview)} />
            <label class="confirm-executable"><input
              type="checkbox"
              name="confirmed"
              value="true"
              checked={@confirmed}
              disabled={@latest.revision != @base.revision || !@matches}
            />I approve these exact check declarations, including changes and removals, for future battles.</label>
            <button
              class="button"
              disabled={@latest.revision != @base.revision || !@matches}
              phx-disable-with="Saving…"
            >Save checks</button>
          </.form>
        </div>
      </section>
      <section class="panel" aria-labelledby="saved-checks-title">
        <h2 id="saved-checks-title">Saved project checks · revision {@latest.revision}</h2>
        <.declarations checks={@latest.definition["checks"]} />
        <details id="checks-history" phx-mounted={Phoenix.LiveView.JS.ignore_attributes("open")}>
          <summary>Recent check revisions · latest five</summary>
          <details
            :for={revision <- @history}
            id={"checks-revision-#{revision.revision}"}
            phx-mounted={Phoenix.LiveView.JS.ignore_attributes("open")}
          >
            <summary>
              Revision {revision.revision} · {Calendar.strftime(
                revision.inserted_at,
                "%Y-%m-%d %H:%M UTC"
              )}
            </summary>
            <.declarations checks={revision.definition["checks"]} />
          </details>
        </details>
      </section>
    </Layouts.workspace>
    """
  end

  defp declarations(assigns) do
    ~H"""
    <p :if={@checks == []}>No checks declared. This does not mean verification has passed.</p>
    <article :for={check <- @checks} class="team-role">
      <h4>{check["name"]}</h4>
      <p class="fine-print">Exact executable and argument array:</p>
      <pre class="draft-copy">{Jason.encode!([check["executable"] | check["arguments"]])}</pre>
      <p class="draft-copy">Directory: {check["directory"]} · Timeout: {check["timeout_seconds"]}s</p>
    </article>
    """
  end
end
