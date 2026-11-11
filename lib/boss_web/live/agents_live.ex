defmodule BossWeb.AgentsLive do
  use BossWeb, :live_view
  alias Boss.Agents.Roles

  @agents [
    %{
      id: :codex,
      name: "Codex",
      docs: "https://developers.openai.com/codex/cli",
      login: "codex login"
    },
    %{
      id: :claude,
      name: "Claude Code",
      docs: "https://code.claude.com/docs/en/setup",
      login: "claude auth login"
    },
    %{
      id: :cursor,
      name: "Cursor Agent",
      docs: "https://cursor.com/docs/cli/overview",
      login: "agent login"
    },
    %{
      id: :hermes,
      name: "Hermes",
      docs: "https://hermes-agent.nousresearch.com/docs/getting-started/installation",
      login: "hermes auth add"
    },
    %{
      id: :pi,
      name: "Pi",
      docs: "https://pi.dev/docs/latest/quickstart",
      login: "pi auth login"
    },
    %{
      id: :opencode,
      name: "OpenCode",
      docs: "https://opencode.ai/docs/cli/",
      login: "opencode auth login"
    }
  ]
  @capabilities [
    headless: "Headless mode",
    streaming: "Streaming output",
    session_resume: "Session resume",
    structured_output: "Structured output",
    approval_support: "Approval controls",
    usage_reporting: "Usage reporting"
  ]

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "Agents · BOSS",
       agents: @agents,
       roles: Roles.list(),
       role_name: "",
       role_error: nil,
       results: %{},
       detecting: false,
       checked_at: nil,
       error: nil
     )}
  end

  @impl true
  def handle_event("detect", _, %{assigns: %{detecting: true}} = socket), do: {:noreply, socket}

  def handle_event("create_role", %{"name" => name}, socket) do
    case Roles.create(name) do
      {:ok, _} ->
        {:noreply, assign(socket, roles: Roles.list(), role_name: "", role_error: nil)}

      {:error, changeset} ->
        {:noreply, assign(socket, role_name: name || "", role_error: role_error(changeset))}
    end
  end

  def handle_event("update_role", %{"role_id" => id, "name" => name}, socket) do
    case Roles.update(id, name) do
      {:ok, _} ->
        {:noreply, assign(socket, roles: Roles.list(), role_error: nil)}

      {:error, :not_found} ->
        {:noreply,
         assign(socket, roles: Roles.list(), role_error: "That role is no longer available.")}

      {:error, :standard} ->
        {:noreply, assign(socket, role_error: standard_message())}

      {:error, changeset} ->
        {:noreply, assign(socket, role_error: role_error(changeset))}
    end
  end

  def handle_event("delete_role", %{"role_id" => id}, socket) do
    case Roles.delete(id) do
      {:ok, _} ->
        {:noreply, assign(socket, roles: Roles.list(), role_error: nil)}

      {:error, :standard} ->
        {:noreply, assign(socket, role_error: standard_message())}

      {:error, :not_found} ->
        {:noreply, assign(socket, roles: Roles.list(), role_error: nil)}
    end
  end

  def handle_event("assign_role", %{"role_id" => id} = params, socket) do
    agents =
      case params["agents"] do
        list when is_list(list) -> list
        _ -> []
      end

    case Roles.assign(id, agents) do
      {:ok, _} ->
        {:noreply, assign(socket, roles: Roles.list(), role_error: nil)}

      {:error, :not_found} ->
        {:noreply,
         assign(socket, roles: Roles.list(), role_error: "That role is no longer available.")}

      {:error, :unknown_agent} ->
        {:noreply, assign(socket, role_error: "Choose an agent from the installed list.")}
    end
  end

  def handle_event("detect", _, socket) do
    detector = Application.get_env(:boss, :agent_detector, Boss.Agents.Detector)

    {:noreply,
     socket
     |> assign(detecting: true, error: nil)
     |> start_async(:detect, fn -> detector.scan() end)}
  end

  @impl true
  def handle_async(:detect, {:ok, {:ok, results}}, socket) do
    {:noreply,
     assign(socket,
       results: Map.new(results, &{&1.id, &1}),
       detecting: false,
       checked_at: DateTime.utc_now() |> DateTime.truncate(:second),
       error: nil
     )}
  end

  def handle_async(:detect, {:ok, {:error, reason}}, socket),
    do: {:noreply, assign(socket, detecting: false, error: scan_error(reason))}

  def handle_async(:detect, _failure, socket),
    do: {:noreply, assign(socket, detecting: false, error: scan_error(:cancelled))}

  @impl true
  def render(assigns) do
    ~H"""
    <header class="app-page-header flex flex-col items-start gap-5 sm:flex-row sm:items-end sm:justify-between">
      <div>
        <p class="app-eyebrow">Local tools</p>
        <h1 class="app-page-title">Agents</h1>
        <p class="app-page-description">Your tools. Your accounts. One workspace.</p>
      </div>
      <button
        id="detect-agents"
        type="button"
        phx-click="detect"
        disabled={@detecting}
        aria-describedby="agents-help"
        class="app-button-primary shrink-0 px-5 py-3 font-semibold disabled:opacity-50"
      >{if @detecting, do: "Detecting…", else: "Detect agents"}</button>
    </header>
    <section id="roles" aria-labelledby="roles-title" class="mt-8">
      <h2 id="roles-title" class="app-panel-heading">Roles</h2>
      <p id="roles-help" class="mt-2 max-w-3xl text-sm leading-6 text-body">
        Reviewer, Implementer, and Analytic are the standard roles. A role can
        include any of the agents below, and an agent can belong to several
        roles. An assignment records the roster. A workflow still runs an agent
        only through that agent's existing runner.
      </p>
      <form id="create-role" phx-submit="create_role" class="mt-4 flex flex-wrap items-end gap-3">
        <div class="min-w-0 flex-1">
          <label for="role-name" class="block text-sm font-medium">New role</label>
          <input
            id="role-name"
            name="name"
            value={@role_name}
            required
            maxlength="80"
            autocomplete="off"
            class="app-field mt-1 w-full min-w-0 px-3 py-2 text-sm"
          />
        </div>
        <button type="submit" class="app-button-secondary px-4 py-2 text-sm font-semibold">
          Create role
        </button>
      </form>
      <p :if={@role_error} id="role-error" role="alert" class="mt-3 text-sm text-warning">
        {@role_error}
      </p>
      <div class="mt-4 grid min-w-0 gap-4">
        <article :for={role <- @roles} id={"role-#{role.id}"} class="app-panel">
          <div :if={role.standard}>
            <h3 id={"role-#{role.id}-title"} class="text-base font-semibold">{role.name}</h3>
            <p id={"role-#{role.id}-purpose"} class="mt-1 text-sm leading-6 text-body">
              {role.purpose}
            </p>
          </div>
          <form
            :if={!role.standard}
            id={"role-#{role.id}-name"}
            phx-submit="update_role"
            class="flex flex-wrap items-end gap-3"
          >
            <input type="hidden" name="role_id" value={role.id} />
            <div class="min-w-0 flex-1">
              <label for={"role-#{role.id}-name-input"} class="block text-sm font-medium">
                Role name
              </label>
              <input
                id={"role-#{role.id}-name-input"}
                name="name"
                value={role.name}
                required
                maxlength="80"
                autocomplete="off"
                class="app-field mt-1 w-full min-w-0 px-3 py-2 text-sm"
              />
            </div>
            <button type="submit" class="app-button-secondary px-4 py-2 text-sm font-semibold">
              Save name
            </button>
            <button
              type="button"
              id={"role-#{role.id}-delete"}
              phx-click="delete_role"
              phx-value-role_id={role.id}
              class="app-button-danger px-4 py-2 text-sm font-semibold"
            >
              Remove role
            </button>
          </form>
          <form id={"role-#{role.id}-agents"} phx-change="assign_role" class="mt-4">
            <input type="hidden" name="role_id" value={role.id} />
            <fieldset>
              <legend class="text-sm font-medium">Agents in this role</legend>
              <div class="mt-3 flex flex-wrap gap-x-5 gap-y-2">
                <label :for={agent <- @agents} class="flex items-center gap-2 text-sm">
                  <input
                    id={"role-#{role.id}-agent-#{agent.id}"}
                    type="checkbox"
                    name="agents[]"
                    value={agent.id}
                    checked={Atom.to_string(agent.id) in role.agent_ids}
                  />
                  {agent.name}
                </label>
              </div>
            </fieldset>
          </form>
        </article>
      </div>
    </section>
    <div class="mt-8 border-y border-line py-5">
      <p id="agents-help" class="max-w-3xl text-sm leading-6 text-body">
        Detect checks the CLIs installed on this computer. It makes no model request and
        does not verify provider access or quota. Sign-in status is reported by each CLI;
        BOSS does not read credential files.
      </p>
      <p id="agents-status" role="status" class="mt-3 min-h-5 text-sm font-medium text-ink">
        <%= cond do %>
          <% @detecting -> %>
            Detecting agents…
          <% @checked_at && is_nil(@error) -> %>
            Detection complete.
          <% true -> %>
            Choose Detect agents to check installed CLIs.
        <% end %>
      </p>
      <p :if={@checked_at} class="mt-2 text-sm text-muted">
        Last completed scan:
        <time id="agents-checked-at" datetime={DateTime.to_iso8601(@checked_at)}>
          {Calendar.strftime(@checked_at, "%Y-%m-%d %H:%M:%S UTC")}
        </time>
      </p>
    </div>
    <div
      :if={@error}
      id="agents-error"
      role="alert"
      class="mt-4 rounded-sm border border-warning-line px-4 py-3 text-sm text-warning bg-warning-soft"
    >
      <p>Latest scan failed. {@error}</p>
      <p :if={@checked_at} class="mt-1">Showing the last completed scan.</p>
    </div>
    <div
      id="agents"
      aria-busy={@detecting}
      class="mt-6 grid min-w-0 gap-6 md:grid-cols-2"
    >
      <.agent :for={agent <- @agents} agent={agent} result={@results[agent.id]} />
    </div>
    """
  end

  attr :agent, :map, required: true
  attr :result, :any, required: true

  defp agent(assigns) do
    assigns = assign(assigns, capabilities: @capabilities)

    ~H"""
    <section
      id={"agent-#{@agent.id}"}
      aria-labelledby={"agent-title-#{@agent.id}"}
      class="app-panel flex min-w-0 flex-col"
    >
      <div class="flex flex-wrap items-center justify-between gap-2">
        <h2 id={"agent-title-#{@agent.id}"} class="app-panel-heading">{@agent.name}</h2>
        <p class="app-badge">
          {if @result, do: probe_status(@result.probe_status), else: "Not checked"}
        </p>
      </div>
      <div :if={@result} class="mt-4 space-y-4 text-sm">
        <dl class="space-y-3">
          <div>
            <dt class="text-muted">Version</dt><dd class="mt-1 font-mono">
              {@result.version || "Not reported"}
            </dd>
          </div>
          <div>
            <dt class="text-muted">Executable</dt><dd class="mt-1 break-all font-mono">
              {@result.path || "Not found on PATH"}
            </dd>
          </div>
          <div>
            <dt class="text-muted">Local sign-in report</dt><dd class="mt-1">
              {auth_status(@result.auth_status)}
            </dd>
          </div>
        </dl>
        <div>
          <h3 class="font-semibold">Capabilities advertised by CLI help</h3>
          <dl class="mt-3 space-y-2 border-t border-line pt-3">
            <div
              :for={{key, label} <- @capabilities}
              data-capability={key}
              class="flex flex-wrap justify-between gap-2"
            >
              <dt class="text-muted">{label}</dt><dd>
                {capability_status(@result.capabilities[key])}
              </dd>
            </div>
          </dl>
        </div>
        <ul
          :if={@result.errors != []}
          aria-label={"#{@agent.name} detection issues"}
          class="space-y-1 text-warning"
        >
          <li :for={error <- @result.errors}>{probe_error(error)}</li>
        </ul>
      </div>
      <div class="mt-6 space-y-3 border-t border-line pt-4 text-sm text-body">
        <.link
          href={@agent.docs}
          class="text-forest underline underline-offset-4 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-forest"
        >
          Official {@agent.name} installation and setup
        </.link>
        <p>
          To sign in, run
          <code class="break-all rounded bg-surface px-1 py-0.5 text-ink">{@agent.login}</code>
          in your terminal.
        </p>
      </div>
    </section>
    """
  end

  defp probe_status(:ok), do: "CLI metadata recognized"
  defp probe_status(:missing), do: "Not found on PATH"
  defp probe_status(:unsupported), do: "CLI metadata unsupported"
  defp probe_status(_), do: "Detection incomplete"

  defp auth_status(:configured), do: "CLI reports credentials configured"
  defp auth_status(:not_configured), do: "CLI reports no credentials configured"
  defp auth_status(_), do: "Unknown"

  defp capability_status(:advertised), do: "Advertised"
  defp capability_status(:not_advertised), do: "Not advertised"
  defp capability_status(_), do: "Unknown"

  defp probe_error(error) do
    stage = %{version: "Version", help: "Help", auth: "Sign-in"}[error.stage] || "CLI"

    reason =
      %{
        timeout: "timed out",
        output_limit: "exceeded its output limit",
        unrecognized: "returned unrecognized output",
        unsupported: "is not supported"
      }[error.reason] || "could not finish"

    "#{stage} check #{reason}."
  end

  defp standard_message, do: "Reviewer, Implementer, and Analytic stay in place."

  defp role_error(%Ecto.Changeset{} = changeset) do
    options = changeset.errors |> Keyword.get_values(:name) |> Enum.map(&elem(&1, 1))

    cond do
      Enum.any?(options, &(&1[:validation] == :required)) -> "Enter a role name."
      Enum.any?(options, &(&1[:constraint] == :unique)) -> "A role with that name already exists."
      Enum.any?(options, &(&1[:validation] == :length)) -> "Use 80 characters or fewer."
      true -> "The role could not be saved."
    end
  end

  defp scan_error(:busy), do: "Another detection is running. Try Detect agents again shortly."
  defp scan_error(:cancelled), do: "Detection was interrupted. Try again."
  defp scan_error(_), do: "Agent detection is unavailable. Try again."
end
