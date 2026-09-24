defmodule CuckodingWeb.AgentSettingsLive do
  use CuckodingWeb, :live_view

  alias Cuckoding.ActivityStream
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
       step: 1,
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
            "reasoning_effort" => "",
            "authorization_account_id" => "auto"
          }),
        else: form

    form =
      if form["model_choice"] != socket.assigns.form["model_choice"],
        do: Map.put(form, "reasoning_effort", ""),
        else: form

    {:noreply, assign(socket, form: form)}
  end

  def handle_event("next", %{"agent" => params}, %{assigns: %{step: 1}} = socket) do
    form = Map.merge(socket.assigns.form, params)

    if String.trim(form["label"] || "") == "" do
      {:noreply, assign(socket, error: "Enter a name for this agent.")}
    else
      {:noreply, assign(socket, form: form, step: 2, error: nil)}
    end
  end

  def handle_event("detect_runtime", _params, socket) do
    form = socket.assigns.form

    if socket.assigns.step == :edit or
         (socket.assigns.step == 2 and form["provider_account_id"] == "") do
      case RuntimeConfiguration.default_executable(form["adapter_key"]) do
        "" ->
          {:noreply,
           assign(socket,
             notice:
               "No executable found in standard locations. Install the command-line tool, or enter its path manually. Your current path was kept.",
             error: nil
           )}

        path ->
          {:noreply,
           assign(socket,
             form: Map.put(form, "executable_path", path),
             notice:
               "Found an installed executable. You can change the path before saving. Sign-in checks compatibility separately.",
             error: nil
           )}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("prepare", %{"agent" => params}, %{assigns: %{step: 2}} = socket) do
    form = Map.merge(socket.assigns.form, params)

    case ProjectOnboarding.save_agent(Map.merge(form, %{"model" => "", "reasoning_effort" => ""})) do
      {:ok, account} ->
        step =
          if account.status == "authenticated" or
               account.adapter_key not in ["codex", "cursor_agent"], do: 3, else: 2

        {:noreply,
         socket
         |> refresh()
         |> assign(
           form: Map.put(form, "provider_account_id", account.id),
           step: step,
           error: nil,
           notice:
             if(step == 3,
               do: "Agent saved. Choose its model.",
               else: "Agent saved. Sign in below, then check the connection."
             )
         )}

      {:error, reason} ->
        {:noreply, assign(socket, form: form, error: error_message(reason))}
    end
  end

  def handle_event(
        "back",
        _params,
        %{assigns: %{step: 2, form: %{"provider_account_id" => id}}} = socket
      )
      when is_binary(id) and id != "",
      do:
        {:noreply,
         assign(socket, error: "This agent is already saved. Close setup or finish sign-in.")}

  def handle_event("back", _params, socket) do
    step = if socket.assigns.step == 3, do: 2, else: 1
    {:noreply, assign(socket, step: step, error: nil)}
  end

  def handle_event("continue", _params, %{assigns: %{step: 2}} = socket) do
    case Adapters.get_provider_account(socket.assigns.form["provider_account_id"]) do
      %{status: "authenticated"} ->
        {:noreply, assign(socket, step: 3, error: nil)}

      %{adapter_key: runtime} when runtime not in ["codex", "cursor_agent"] ->
        {:noreply, assign(socket, step: 3, error: nil)}

      _other ->
        {:noreply, assign(socket, error: "Check sign-in before choosing a model.")}
    end
  end

  def handle_event("save", %{"agent" => params}, socket) do
    params = Map.merge(socket.assigns.form, params)

    params =
      if params["model_choice"] == "custom",
        do: params,
        else: Map.put(params, "model", params["model_choice"])

    params = Map.put(params, "provider_account_id", socket.assigns.form["provider_account_id"])

    result =
      with {:ok, params} <- locked_setup_params(params, socket.assigns.step),
           do: ProjectOnboarding.save_agent(params)

    case result do
      {:ok, account} ->
        {:noreply,
         socket
         |> refresh()
         |> assign(
           form: empty_form(),
           step: 1,
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

        {:noreply, assign(socket, form: form, step: :edit, error: nil)}
    end
  end

  def handle_event("cancel", _params, socket) do
    notice =
      if socket.assigns.step in [2, 3] and socket.assigns.form["provider_account_id"] != "",
        do: "Agent remains saved. You can finish sign-in from its card below.",
        else: nil

    {:noreply, assign(socket, form: empty_form(), step: 1, error: nil, notice: notice)}
  end

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

    step =
      if socket.assigns.step == 2 and socket.assigns.form["provider_account_id"] == account.id and
           account.status == "authenticated",
         do: 3,
         else: socket.assigns.step

    {:noreply, socket |> refresh() |> assign(checking: nil, notice: message, step: step)}
  end

  def handle_async(:authorization, {:ok, {:error, %{code: :unsupported_version}}}, socket) do
    {:noreply,
     assign(socket,
       checking: nil,
       notice: nil,
       error:
         "This executable's version is not supported. Close setup and use Edit agent to choose a supported CLI, then check sign-in again."
     )}
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
      |> assign(:reasoning_options, reasoning_options(assigns.form, assigns.accounts))
      |> assign(
        :wizard_account,
        Enum.find(assigns.accounts, &(&1.id == assigns.form["provider_account_id"]))
      )

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
          phx-submit={if @step == 1, do: "next", else: if(@step == 2, do: "prepare", else: "save")}
          class="space-y-4 rounded-xl border border-slate-300 bg-white p-5"
        >
          <h2 class="text-xl font-semibold">
            {if @step == :edit, do: "Edit shared agent", else: "Add agent"}
          </h2>
          <p :if={@step != :edit} role="status" aria-live="polite" class="sr-only">
            Step {@step} of 3: {Enum.at(["Name and runtime", "Authorization", "Model"], @step - 1)}
          </p>
          <ol :if={@step != :edit} class="grid gap-2 sm:grid-cols-3" aria-label="Agent setup progress">
            <li
              :for={{label, number} <- [{"Name and runtime", 1}, {"Authorization", 2}, {"Model", 3}]}
              aria-current={if @step == number, do: "step"}
              class={
                if @step == number,
                  do: "rounded border border-slate-950 bg-slate-950 p-3 text-white",
                  else: "rounded border border-slate-300 p-3"
              }
            >
              {number}. {label}
            </li>
          </ol>
          <div :if={@step in [1, :edit]} class="grid gap-4 sm:grid-cols-2">
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
          </div>
          <div :if={@step in [2, :edit]} class="grid gap-4">
            <p id="runtime-path-help" class="text-sm text-slate-600">
              We check standard install locations automatically. You can edit the path or search again after installing a runtime.
            </p>
            <p :if={@form["adapter_key"] == "codex"} class="text-sm text-slate-600">
              Codex Desktop (including ChatGPT.app) is also checked. Sign in separately for Cuckoding.
              Supported CLI version: {Cuckoding.Adapters.Codex.supported_version()}.
            </p>
            <p :if={@form["executable_path"] == ""} class="text-sm text-amber-900">
              No executable was found. Install the command-line tool and choose Find automatically, or enter its path below.
            </p>
            <label class="grid gap-2">
              Runtime executable
              <input
                name="agent[executable_path]"
                value={@form["executable_path"]}
                aria-describedby="runtime-path-help"
                required
                readonly={@step == 2 and @wizard_account != nil}
                autocomplete="off"
                autocapitalize="none"
                spellcheck="false"
                placeholder="/absolute/path/to/agent"
                class="min-h-11 min-w-0 rounded border border-slate-400 px-3 font-mono text-sm"
              />
            </label>
            <button
              :if={@step == :edit or @wizard_account == nil}
              id="detect-runtime"
              type="button"
              phx-click="detect_runtime"
              class="min-h-11 justify-self-start rounded border border-slate-400 px-4"
            >
              Find automatically
            </button>
            <label :if={@form["adapter_key"] == "claude_code"} class="grid gap-2">
              Claude API-key helper
              <input
                name="agent[api_key_helper]"
                value={@form["api_key_helper"]}
                required
                readonly={@step == 2 and @wizard_account != nil}
                placeholder="/absolute/path/to/helper"
                class="min-h-11 min-w-0 rounded border border-slate-400 px-3 font-mono text-sm"
              />
            </label>
            <label
              :if={
                @form["provider_account_id"] == "" and
                  @form["adapter_key"] in ["codex", "cursor_agent"]
              }
              class="grid gap-2"
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
                      is_nil(account.authorization_account_id)
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
          </div>
          <div
            :if={@step == 2 and @wizard_account != nil}
            class="space-y-3 rounded-lg border border-slate-200 bg-slate-50 p-4"
          >
            <p class="font-medium">{status_label(@wizard_account.status)}</p>
            <p :if={@wizard_account.authorization_account_id} class="text-sm">
              This agent uses an existing provider sign-in. No second login is needed while it remains valid.
            </p>
            <div
              :if={@setups[@wizard_account.id] && is_nil(@wizard_account.authorization_account_id)}
              id={"wizard-agent-command-#{@wizard_account.id}"}
              phx-hook="CopyCommand"
              class="space-y-2"
            >
              <p class="text-sm">Run this sign-in command in Terminal, then check the connection.</p>
              <label class="grid gap-2 text-sm">
                Sign-in command
                <span class="flex gap-2">
                  <input
                    data-copy-source
                    readonly
                    value={@setups[@wizard_account.id].command}
                    class="min-h-11 min-w-0 flex-1 rounded border border-slate-400 bg-white px-3 font-mono text-xs"
                  />
                  <button
                    type="button"
                    data-copy-button
                    class="min-h-11 rounded border border-slate-400 bg-white px-4"
                  >Copy</button>
                </span>
              </label>
              <p data-copy-status role="status" aria-live="polite" class="min-h-5 text-sm"></p>
            </div>
            <button
              :if={@wizard_account.adapter_key in ["codex", "cursor_agent"]}
              type="button"
              phx-click="check"
              phx-value-id={@wizard_account.id}
              disabled={@checking != nil}
              class="min-h-11 rounded bg-slate-950 px-4 text-white disabled:opacity-60"
            >
              {if @checking == @wizard_account.id,
                do: "Checking sign-in and models…",
                else: "Check sign-in and fetch models"}
            </button>
            <button
              :if={
                @wizard_account.status == "authenticated" or
                  @wizard_account.adapter_key not in ["codex", "cursor_agent"]
              }
              type="button"
              phx-click="continue"
              class="min-h-11 rounded border border-slate-400 bg-white px-4"
            >Continue to model</button>
          </div>
          <div :if={@step in [3, :edit]} class="grid gap-4 sm:grid-cols-2">
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
              Models come from the verified provider account when available. Runtime default leaves the choice to the CLI; Custom model ID is available if discovery is unsupported.
            </p>
            <label :if={@form["adapter_key"] == "codex"} class="grid gap-2">
              Reasoning level
              <select
                name="agent[reasoning_effort]"
                class="min-h-11 min-w-0 rounded border border-slate-400 bg-white px-3"
              >
                <option value="" selected={@form["reasoning_effort"] in [nil, ""]}>
                  Model default
                </option>
                <option
                  :for={effort <- @reasoning_options}
                  value={effort}
                  selected={@form["reasoning_effort"] == effort}
                >
                  {String.capitalize(effort)}
                </option>
              </select>
            </label>
            <p
              :if={@form["adapter_key"] == "codex" and @reasoning_options == []}
              class="text-sm text-slate-600 sm:col-span-2"
            >
              Select a discovered model to see its supported reasoning levels. Model default remains available.
            </p>
            <p :if={@form["adapter_key"] != "codex"} class="text-sm text-slate-600 sm:col-span-2">
              This runtime does not expose a verified reasoning-level control here; it uses its own default.
            </p>
          </div>
          <p :if={@form["adapter_key"] in ["opencode", "custom_agent"]} class="text-sm text-amber-950">
            Setup only: this runtime cannot execute tasks yet.
          </p>
          <div class="flex flex-wrap gap-3">
            <button
              :if={@step != 2 or @wizard_account == nil}
              phx-disable-with="Saving…"
              data-confirm={
                if @step == :edit,
                  do:
                    "Update this shared agent for all projects using it? Existing run snapshots and running processes will not change."
              }
              class="min-h-11 rounded bg-slate-950 px-4 text-white"
            >{case @step do
              1 -> "Continue to authorization"
              2 -> "Save and continue"
              3 -> "Finish agent setup"
              :edit -> "Save agent"
            end}</button>
            <button
              :if={@step in [2, 3] and (@wizard_account == nil or @step == 3)}
              type="button"
              phx-click="back"
              class="min-h-11 rounded border border-slate-400 px-4"
            >Back</button>
            <button
              :if={@step != 1}
              type="button"
              phx-click="cancel"
              class="min-h-11 rounded border border-slate-400 px-4"
            >{if @step == :edit, do: "Cancel edit", else: "Close setup"}</button>
          </div>
        </form>
        <p :if={@accounts == []}>No saved agents yet. Add your first agent above.</p>
        <article
          :for={account <- @accounts}
          :if={@step != 2 or is_nil(@wizard_account) or account.id != @wizard_account.id}
          id={"agent-#{account.id}"}
          class="space-y-4 rounded-xl border border-slate-300 bg-white p-5"
        >
          <div class="flex flex-wrap justify-between gap-3">
            <div>
              <h2 class="text-xl font-semibold">{account.label}</h2>
              <p>{runtime_label(account.adapter_key)}</p>
              <p class={
                if account.status == "authenticated",
                  do: "font-semibold text-emerald-800",
                  else: "font-semibold text-amber-800"
              }>
                {status_label(account.status)}
              </p>
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
          <details
            :if={
              is_nil(account.authorization_account_id) and
                List.wrap(@failures[account.id]) != []
            }
            phx-mounted={JS.ignore_attributes("open")}
            class="rounded-lg border border-red-200 bg-red-50 p-4 text-sm text-red-950"
          >
            <summary class="min-h-6 cursor-pointer font-semibold">
              Recent agent errors ({length(@failures[account.id])})
            </summary>
            <p class="mt-2">Durable, redacted failures for this shared sign-in, newest first.</p>
            <ol class="mt-3 space-y-2">
              <li :for={event <- @failures[account.id]}>
                <span class="font-medium">{event.public_summary}</span>
                <span class="block text-red-900">
                  {Calendar.strftime(event.occurred_at, "%Y-%m-%d %H:%M:%S UTC")} · code
                  <code>{event.metadata["code"]}</code>
                </span>
              </li>
            </ol>
          </details>
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
            <details
              phx-mounted={JS.ignore_attributes("open")}
              open={account.status != "authenticated"}
            >
              <summary class="min-h-11 cursor-pointer font-medium">
                {if account.status == "authenticated", do: "Re-authorize agent", else: "Sign in once"}
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

    failures =
      accounts
      |> Enum.filter(&is_nil(&1.authorization_account_id))
      |> Map.new(fn account ->
        events =
          "provider:#{account.id}"
          |> ActivityStream.list(0)
          |> Enum.filter(&String.ends_with?(&1.event_type, "_failed"))
          |> Enum.reverse()

        {account.id, events}
      end)

    assign(socket, accounts: accounts, setups: setups, impacts: impacts, failures: failures)
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
      "reasoning_effort" => "",
      "authorization_account_id" => "auto"
    }

  defp locked_setup_params(params, 3) do
    case Adapters.get_provider_account(params["provider_account_id"]) do
      nil ->
        {:error, :provider_account_not_found}

      account ->
        settings = account.capabilities_json["settings"] || %{}

        {:ok,
         Map.merge(params, %{
           "label" => account.label,
           "adapter_key" => account.adapter_key,
           "authorization_account_id" => account.authorization_account_id || "",
           "executable_path" => settings["executable_path"],
           "api_key_helper" => settings["api_key_helper"]
         })}
    end
  end

  defp locked_setup_params(params, :edit), do: {:ok, params}
  defp locked_setup_params(_params, _step), do: {:error, :invalid_setup_step}

  defp model_choice(account, accounts) do
    model = get_in(account.capabilities_json, ["settings", "model"]) || ""

    if model == "" or
         Enum.any?(model_options_for_account(account, accounts), &(elem(&1, 1) == model)),
       do: model,
       else: "custom"
  end

  defp model_options(form, accounts) do
    case form_account(form, accounts) do
      nil -> RuntimeConfiguration.models(form["adapter_key"])
      account -> model_options_for_account(account, accounts)
    end
  end

  defp form_account(form, accounts) do
    case form["provider_account_id"] do
      id when is_binary(id) and id != "" -> Enum.find(accounts, &(&1.id == id))
      _other -> selected_authorization(form, accounts)
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
    root = authorization_root(account, accounts)

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

  defp reasoning_options(%{"adapter_key" => "codex"} = form, accounts) do
    models =
      case form |> form_account(accounts) |> authorization_root(accounts) do
        nil -> []
        root -> get_in(root.capabilities_json, ["model_catalog", "models"]) || []
      end

    selected =
      if form["model_choice"] in [nil, ""],
        do: Enum.find(models, &(&1["is_default"] == true)),
        else: Enum.find(models, &(&1["id"] == form["model_choice"]))

    (selected && selected["reasoning_efforts"]) || []
  end

  defp reasoning_options(_form, _accounts), do: []

  defp authorization_root(nil, _accounts), do: nil
  defp authorization_root(%{authorization_account_id: nil} = account, _accounts), do: account

  defp authorization_root(account, accounts),
    do: Enum.find(accounts, &(&1.id == account.authorization_account_id))

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

  defp error_message(:invalid_reasoning_effort),
    do: "Choose a reasoning level supported by the selected Codex model, or use Model default."

  defp error_message(:provider_account_not_found),
    do: "This saved agent no longer exists. Start setup again."

  defp error_message(:authorization_identity_immutable),
    do:
      "Add a new agent to choose another sign-in. Existing agent sign-ins stay linked to preserve run history."

  defp error_message(_reason),
    do:
      "Could not save this agent. Check the name, executable and helper paths; use a different name if it is already taken."
end
