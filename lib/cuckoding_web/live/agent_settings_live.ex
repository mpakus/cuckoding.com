defmodule CuckodingWeb.AgentSettingsLive do
  use CuckodingWeb, :live_view

  alias Cuckoding.Adapters
  alias Cuckoding.Adapters.RuntimeConfiguration
  alias Cuckoding.AgentRuntime
  alias Cuckoding.ProjectOnboarding

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Phoenix.PubSub.subscribe(Cuckoding.PubSub, "activity")

    {:ok,
     socket
     |> assign(
       page_title: "Agents",
       form: empty_form(),
       checking: nil,
       disconnecting: nil,
       error: nil,
       notice: nil
     )
     |> refresh()}
  end

  @impl true
  def handle_event("change", %{"agent" => params}, socket) do
    form = Map.merge(socket.assigns.form, params)

    form =
      if form["adapter_key"] != socket.assigns.form["adapter_key"],
        do:
          Map.merge(form, %{
            "executable_path" => RuntimeConfiguration.default_executable(form["adapter_key"]),
            "model" => "",
            "model_choice" => "",
            "authorization_account_id" => "auto"
          }),
        else: form

    {:noreply, assign(socket, form: form)}
  end

  def handle_event("save", %{"agent" => params}, socket) do
    params = Map.merge(socket.assigns.form, params)

    params =
      if params["model_choice"] == "custom",
        do: params,
        else: Map.put(params, "model", params["model_choice"])

    params = Map.put(params, "provider_account_id", socket.assigns.form["provider_account_id"])

    case ProjectOnboarding.save_agent(params) do
      {:ok, account} ->
        {:noreply,
         socket
         |> refresh()
         |> assign(
           form: empty_form(),
           error: nil,
           notice: saved_message(account)
         )}

      {:error, reason} ->
        {:noreply, assign(socket, error: error_message(reason))}
    end
  end

  def handle_event("edit", %{"id" => id}, socket) do
    case Adapters.get_provider_account(id) do
      nil ->
        {:noreply, assign(socket, error: "Agent no longer exists. Reload this page.")}

      account ->
        form =
          Map.merge(account.capabilities_json["settings"] || %{}, %{
            "provider_account_id" => id,
            "label" => account.label,
            "adapter_key" => account.adapter_key,
            "authorization_account_id" => account.authorization_account_id || "",
            "model_choice" => model_choice(account, socket.assigns.accounts)
          })

        {:noreply, assign(socket, form: form, error: nil)}
    end
  end

  def handle_event("cancel", _params, socket),
    do: {:noreply, assign(socket, form: empty_form(), error: nil)}

  def handle_event("check", %{"id" => id}, %{assigns: %{checking: nil}} = socket) do
    case Adapters.get_provider_account(id) do
      nil ->
        {:noreply, assign(socket, error: "Agent no longer exists. Reload this page.")}

      account ->
        {:noreply,
         socket
         |> assign(checking: id, error: nil, notice: "Checking #{account.label}…")
         |> start_async(:authorization, fn -> AgentRuntime.check_account(account) end)}
    end
  end

  def handle_event("check", _params, socket), do: {:noreply, socket}

  def handle_event("disconnect", %{"id" => id}, %{assigns: %{disconnecting: nil}} = socket) do
    case Adapters.get_provider_account(id) do
      %{authorization_account_id: nil} = account ->
        {:noreply,
         socket
         |> assign(disconnecting: id, error: nil, notice: "Disconnecting #{account.label}…")
         |> start_async(:disconnect, fn -> AgentRuntime.disconnect_account(account) end)}

      _other ->
        {:noreply, assign(socket, error: "That shared sign-in is no longer available.")}
    end
  end

  def handle_event("disconnect", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_async(:authorization, {:ok, {:ok, account}}, socket) do
    message = authorization_message(account)

    {:noreply, socket |> refresh() |> assign(checking: nil, notice: message)}
  end

  def handle_async(:authorization, _result, socket) do
    {:noreply,
     assign(socket,
       checking: nil,
       notice: nil,
       error:
         "Could not check sign-in. Verify the executable and supported CLI version, then try again."
     )}
  end

  def handle_async(:disconnect, {:ok, {:ok, account}}, socket) do
    {:noreply,
     socket
     |> refresh()
     |> assign(
       disconnecting: nil,
       notice:
         "#{account.label} was disconnected. New runs using its shared sign-in now require authorization."
     )}
  end

  def handle_async(:disconnect, _result, socket) do
    {:noreply,
     assign(socket,
       disconnecting: nil,
       notice: nil,
       error:
         "Could not disconnect this provider sign-in. No saved agent settings were changed. Try the provider CLI logout command directly."
     )}
  end

  @impl true
  def handle_info({:activity_event, "provider:" <> _id, _sequence}, socket),
    do: {:noreply, refresh(socket)}

  def handle_info(_message, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    assigns =
      assigns
      |> assign(:runtime_options, RuntimeConfiguration.options())
      |> assign(:model_options, model_options(assigns.form, assigns.accounts))

    ~H"""
    <Layouts.app flash={@flash} active="agent_settings">
      <section class="space-y-6" aria-labelledby="agents-heading">
        <header class="space-y-3">
          <h1 id="agents-heading" class="text-3xl font-semibold text-slate-950">Agents</h1>
          <p>
            Add and sign in once. Choose these agents in any project's settings and assign their roles.
          </p>
          <p
            id="profile-sharing"
            class="rounded-lg border border-amber-300 bg-amber-50 p-4 text-sm text-amber-950"
          >
            Agents can share one provider sign-in while using different models and project roles.
            Shared sign-in also shares provider history. Choose a separate sign-in when histories must stay separate.
            Your personal CLI profile is not used. Cuckoding sets no expiry: sign-in is kept between restarts until you disconnect it or the provider expires or revokes it.
          </p>
        </header>
        <p id="agent-status" role="status" aria-live="polite" class="min-h-6 text-emerald-900">
          {@notice}
        </p>
        <p
          :if={@error}
          id="agent-error"
          role="alert"
          class="rounded border border-red-300 bg-red-50 p-4 text-red-950"
        >
          {@error}
        </p>
        <form
          id="agent-form"
          phx-change="change"
          phx-submit="save"
          class="space-y-4 rounded-xl border border-slate-300 bg-white p-5"
          data-confirm={
            if @form["provider_account_id"] != "",
              do:
                "Update this shared agent for all projects using it? Existing run snapshots and running processes will not change."
          }
        >
          <h2 class="text-xl font-semibold">
            {if @form["provider_account_id"] == "", do: "Add agent", else: "Edit shared agent"}
          </h2>
          <div class="grid gap-4 sm:grid-cols-2">
            <label class="grid gap-2">
              Agent name
              <input
                name="agent[label]"
                value={@form["label"]}
                required
                maxlength="120"
                class="min-h-11 min-w-0 rounded border border-slate-400 px-3"
              />
            </label>
            <label class="grid gap-2">
              Runtime
              <select
                name="agent[adapter_key]"
                class="min-h-11 min-w-0 rounded border border-slate-400 bg-white px-3"
              >
                <option
                  :for={{label, value} <- @runtime_options}
                  value={value}
                  selected={value == @form["adapter_key"]}
                >
                  {label}
                </option>
              </select>
            </label>
            <label class="grid gap-2">
              Model
              <select
                name="agent[model_choice]"
                aria-describedby="model-help"
                class="min-h-11 min-w-0 rounded border border-slate-400 bg-white px-3"
              >
                <option value="" selected={@form["model_choice"] == ""}>Runtime default</option>
                <option
                  :for={{label, value} <- @model_options}
                  value={value}
                  selected={@form["model_choice"] == value}
                >
                  {label}
                </option>
                <option value="custom" selected={@form["model_choice"] == "custom"}>
                  Custom model ID
                </option>
              </select>
            </label>
            <label :if={@form["model_choice"] == "custom"} class="grid gap-2">
              Model ID
              <input
                name="agent[model]"
                value={@form["model"]}
                required
                maxlength="128"
                aria-describedby="model-help"
                class="min-h-11 min-w-0 rounded border border-slate-400 px-3 font-mono text-sm"
              />
            </label>
            <p id="model-help" class="text-sm text-slate-600 sm:col-span-2">
              Check sign-in to refresh models available to this provider account. Runtime default leaves the choice to the CLI; Custom model ID remains available for runtimes without discovery.
            </p>
            <label
              :if={
                @form["provider_account_id"] == "" and
                  @form["adapter_key"] in ["codex", "cursor_agent"]
              }
              class="grid gap-2 sm:col-span-2"
            >
              Provider sign-in
              <select
                name="agent[authorization_account_id]"
                aria-describedby="profile-sharing"
                class="min-h-11 min-w-0 rounded border border-slate-400 bg-white px-3"
              >
                <option value="auto" selected={@form["authorization_account_id"] == "auto"}>
                  Reuse compatible sign-in (or create the first one)
                </option>
                <option
                  :for={account <- @accounts}
                  :if={
                    account.adapter_key == @form["adapter_key"] and
                      account.authorization_account_id == nil
                  }
                  value={account.id}
                  selected={@form["authorization_account_id"] == account.id}
                >
                  Use sign-in from {account.label} · {status_label(account.status)}
                </option>
                <option value="new" selected={@form["authorization_account_id"] == "new"}>
                  Use a separate sign-in
                </option>
              </select>
            </label>
            <label class="grid gap-2 sm:col-span-2">
              Runtime executable
              <input
                name="agent[executable_path]"
                value={@form["executable_path"]}
                required
                class="min-h-11 min-w-0 rounded border border-slate-400 px-3 font-mono text-sm"
              />
            </label>
            <label :if={@form["adapter_key"] == "claude_code"} class="grid gap-2 sm:col-span-2">
              Claude API-key helper
              <input
                name="agent[api_key_helper]"
                value={@form["api_key_helper"]}
                required
                class="min-h-11 min-w-0 rounded border border-slate-400 px-3"
              />
            </label>
          </div>
          <p :if={@form["adapter_key"] in ["opencode", "custom_agent"]} class="text-sm text-amber-950">
            Setup only: this runtime cannot execute tasks yet.
          </p>
          <div class="flex flex-wrap gap-3">
            <button phx-disable-with="Saving…" class="min-h-11 rounded bg-slate-950 px-4 text-white">Save agent</button>
            <button
              :if={@form["provider_account_id"] != ""}
              type="button"
              phx-click="cancel"
              class="min-h-11 rounded border border-slate-400 px-4"
            >Cancel edit</button>
          </div>
        </form>
        <p :if={@accounts == []}>No saved agents yet. Add your first agent above.</p>
        <article
          :for={account <- @accounts}
          id={"agent-#{account.id}"}
          class="space-y-4 rounded-xl border border-slate-300 bg-white p-5"
        >
          <div class="flex flex-wrap justify-between gap-3">
            <div>
              <h2 class="text-xl font-semibold">{account.label}</h2>
              <p>{runtime_label(account.adapter_key)} · {status_label(account.status)}</p>
              <p class="text-sm text-slate-600">
                Model: {get_in(account.capabilities_json, ["settings", "model"]) || "Runtime default"}
              </p>
              <p :if={account.probed_at} class="text-sm text-slate-600">
                Last checked: {Calendar.strftime(account.probed_at, "%Y-%m-%d %H:%M UTC")}
              </p>
              <p
                :if={is_nil(account.authorization_account_id)}
                class="text-sm text-slate-600"
              >
                {model_catalog_label(account)}
              </p>
            </div>
            <button
              type="button"
              phx-click="edit"
              phx-value-id={account.id}
              aria-label={"Edit #{account.label}"}
              class="min-h-11 rounded border border-slate-400 px-4"
            >Edit agent</button>
          </div>
          <p :if={account.authorization_account_id}>
            Uses the existing provider sign-in. No second login is needed while it remains valid.
            <a href={"#agent-#{account.authorization_account_id}"} class="underline">Manage shared sign-in</a>
          </p>
          <section
            :if={is_nil(account.authorization_account_id)}
            id={"agent-impact-#{account.id}"}
            class="space-y-2 rounded-lg bg-slate-50 p-4 text-sm"
          >
            <h3 class="font-semibold">Shared sign-in impact</h3>
            <p>
              {length(@impacts[account.id].agents)} saved {if length(@impacts[account.id].agents) == 1,
                do: "agent uses",
                else: "agents use"} this provider sign-in.
            </p>
            <p :if={@impacts[account.id].projects == []} class="text-slate-600">
              It is not assigned to a current project role.
            </p>
            <ul :if={@impacts[account.id].projects != []} class="list-disc space-y-1 pl-5">
              <li :for={project <- @impacts[account.id].projects}>
                <.link navigate={~p"/projects/#{project.id}/edit"} class="underline">
                  {project.name}
                </.link>
                — {Enum.join(project.roles, ", ")}
              </li>
            </ul>
          </section>
          <div
            :for={setup <- List.wrap(@setups[account.id])}
            :if={is_nil(account.authorization_account_id)}
            class="space-y-3"
          >
            <details open={account.status != "authenticated"}>
              <summary class="min-h-11 cursor-pointer font-medium">
                {if account.status == "authenticated", do: "Reconnect agent", else: "Sign in once"}
              </summary>
              <p class="mb-3 text-sm">
                Run this command in Terminal. Return here when sign-in completes.
              </p>
              <div id={"agent-command-#{account.id}"} phx-hook="CopyCommand" class="space-y-2">
                <label class="grid gap-2">
                  Sign-in command for {account.label}
                  <span class="flex gap-2">
                    <input
                      data-copy-source
                      readonly
                      value={setup.command}
                      class="min-h-11 min-w-0 flex-1 rounded border border-slate-400 px-3 font-mono text-xs"
                    />
                    <button
                      type="button"
                      data-copy-button
                      class="min-h-11 rounded border border-slate-400 px-4"
                    >Copy</button>
                  </span>
                </label>
                <p data-copy-status role="status" aria-live="polite" class="min-h-5 text-sm"></p>
              </div>
            </details>
            <button
              type="button"
              phx-click="check"
              phx-value-id={account.id}
              disabled={@checking != nil}
              class="min-h-11 rounded bg-slate-950 px-4 text-white disabled:opacity-60"
            >{if @checking == account.id,
              do: "Checking sign-in and models…",
              else: "Check sign-in and refresh models"}</button>
            <button
              :if={account.status == "authenticated"}
              type="button"
              phx-click="disconnect"
              phx-value-id={account.id}
              disabled={@disconnecting != nil}
              data-confirm="Disconnect this provider sign-in from Cuckoding? New runs for all listed agents, projects, and roles will stop until you sign in again. Running processes and historical snapshots are unchanged."
              class="min-h-11 rounded border border-red-400 px-4 text-red-950 disabled:opacity-60"
            >{if @disconnecting == account.id, do: "Disconnecting…", else: "Disconnect shared sign-in"}</button>
          </div>
          <p
            :if={account.adapter_key in ["codex", "cursor_agent"] and @setups[account.id] == nil}
            role="alert"
            class="text-red-950"
          >
            Profile setup is blocked. Check the executable and app-owned profile directory; symlinks or modified Cursor security files are not accepted. Do not paste credentials into settings.
          </p>
          <p :if={account.adapter_key == "claude_code"}>
            Uses the saved API-key helper. Access is checked when a run starts.
          </p>
          <p :if={account.adapter_key in ["opencode", "custom_agent"]}>
            Setup only; task execution is not supported yet.
          </p>
        </article>
      </section>
    </Layouts.app>
    """
  end

  defp refresh(socket) do
    accounts = Adapters.list_provider_accounts()

    setups =
      Map.new(accounts, fn account ->
        case AgentRuntime.account_setup(account) do
          {:ok, %{command: _command} = setup} -> {account.id, setup}
          _other -> {account.id, nil}
        end
      end)

    by_authorization =
      accounts
      |> Enum.uniq_by(&Adapters.authorization_id/1)
      |> Map.new(fn account ->
        {Adapters.authorization_id(account), Adapters.provider_account_impact(account)}
      end)

    impacts =
      Map.new(accounts, &{&1.id, by_authorization[Adapters.authorization_id(&1)]})

    assign(socket, accounts: accounts, setups: setups, impacts: impacts)
  end

  defp empty_form,
    do: %{
      "provider_account_id" => "",
      "label" => "",
      "adapter_key" => "codex",
      "executable_path" => RuntimeConfiguration.default_executable("codex"),
      "api_key_helper" => "",
      "model" => "",
      "model_choice" => "",
      "authorization_account_id" => "auto"
    }

  defp model_choice(account, accounts) do
    model = get_in(account.capabilities_json, ["settings", "model"]) || ""

    if model == "" or
         Enum.any?(model_options_for_account(account, accounts), &(elem(&1, 1) == model)),
       do: model,
       else: "custom"
  end

  defp model_options(form, accounts) do
    account =
      case form["provider_account_id"] do
        id when is_binary(id) and id != "" -> Enum.find(accounts, &(&1.id == id))
        _other -> selected_authorization(form, accounts)
      end

    case account do
      nil -> RuntimeConfiguration.models(form["adapter_key"])
      account -> model_options_for_account(account, accounts)
    end
  end

  defp selected_authorization(form, accounts) do
    selected = form["authorization_account_id"]

    if is_binary(selected) and selected not in ["", "auto", "new"] do
      Enum.find(accounts, &(&1.id == selected))
    else
      accounts
      |> Enum.filter(fn account ->
        account.authorization_account_id == nil and account.adapter_key == form["adapter_key"] and
          get_in(account.capabilities_json, ["settings", "executable_path"]) ==
            form["executable_path"]
      end)
      |> Enum.sort_by(&{&1.status != "authenticated", &1.inserted_at, &1.id})
      |> List.first()
    end
  end

  defp model_options_for_account(account, accounts) do
    root =
      if account.authorization_account_id,
        do: Enum.find(accounts, &(&1.id == account.authorization_account_id)),
        else: account

    case root && get_in(root.capabilities_json, ["model_catalog", "models"]) do
      models when is_list(models) and models != [] ->
        Enum.flat_map(models, fn
          %{"id" => id, "label" => label} when is_binary(id) and is_binary(label) ->
            [{label, id}]

          _other ->
            []
        end)

      _other ->
        RuntimeConfiguration.models(account.adapter_key)
    end
  end

  defp authorization_message(%{status: "authenticated"} = account) do
    case get_in(account.capabilities_json, ["model_catalog"]) do
      %{"status" => "available", "models" => models} ->
        "#{account.label} is connected. Refreshed #{length(models)} available models for this shared sign-in."

      %{"status" => "unavailable"} ->
        "#{account.label} is connected, but its model list could not be refreshed. Runtime default and Custom model ID remain available."

      _other ->
        "#{account.label} is connected. Use it in any project; runs check access automatically."
    end
  end

  defp authorization_message(account),
    do: "#{account.label} needs sign-in. Run its command, then check again."

  defp model_catalog_label(account) do
    case get_in(account.capabilities_json, ["model_catalog"]) do
      %{"status" => "available", "models" => models} ->
        "Available models: #{length(models)} · refreshes with sign-in check"

      %{"status" => "unavailable"} ->
        "Model list unavailable · check sign-in again to retry"

      _other ->
        "Available models load after sign-in"
    end
  end

  defp saved_message(%{authorization_account_id: id, label: label}) when is_binary(id),
    do: "#{label} saved with the existing provider sign-in. No separate login is needed."

  defp saved_message(account),
    do: "#{account.label} saved. Sign in below once, then reuse it for other agents and projects."

  defp runtime_label(key),
    do:
      Enum.find_value(RuntimeConfiguration.options(), key, fn {label, value} ->
        if value == key, do: label
      end)

  defp status_label("authenticated"), do: "Connected"
  defp status_label("authentication_required"), do: "Sign-in required"
  defp status_label(_status), do: "Not checked"

  defp error_message(:invalid_runtime_executable),
    do: "Choose an absolute path to an executable runtime."

  defp error_message(:provider_account_mismatch),
    do:
      "Choose a sign-in with the same runtime and executable path, or choose a separate sign-in. An existing agent cannot change runtime."

  defp error_message(:agent_label_required), do: "Enter a name for this agent."

  defp error_message(:invalid_model),
    do:
      "Enter a model ID of up to 128 letters, digits, dots, slashes, colons, underscores or hyphens."

  defp error_message(:authorization_identity_immutable),
    do:
      "Add a new agent to choose another sign-in. Existing agent sign-ins stay linked to preserve run history."

  defp error_message(_reason),
    do:
      "Could not save this agent. Check the name, executable and helper paths; use a different name if it is already taken."
end
