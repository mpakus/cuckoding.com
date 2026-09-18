defmodule CuckodingWeb.PluginSettingsLive do
  use CuckodingWeb, :live_view

  alias Cuckoding.Diagnostics
  alias Cuckoding.Plugins

  @actor "local-user"

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(page_title: "Plugin settings", notice: "", error: "", diagnostics_path: nil)
     |> load()}
  end

  @impl true
  def handle_event("refresh", _params, socket) do
    result = Plugins.refresh()
    finish(socket, {:ok, result}, "Plugin detection refreshed.")
  end

  def handle_event("export_diagnostics", _params, socket) do
    case Diagnostics.export() do
      {:ok, path} ->
        {:noreply,
         assign(socket,
           diagnostics_path: path,
           notice: "Diagnostics bundle created for review.",
           error: ""
         )}

      {:error, _reason} ->
        {:noreply,
         assign(socket,
           diagnostics_path: nil,
           notice: "",
           error: "Diagnostics export failed. No bundle was created."
         )}
    end
  end

  def handle_event("enable", %{"plugin_id" => plugin_id} = params, socket) do
    if params["confirmed"] == "true" do
      with plugin when not is_nil(plugin) <- Plugins.get(plugin_id),
           permissions <-
             Map.put(plugin.manifest_json["permissions"], "network", params["network"]),
           result <-
             Plugins.enable(plugin_id, params["scope_type"], params["scope_id"], %{
               "permissions" => permissions,
               "approval_kind" => approval_kind(params["network"]),
               "actor" => @actor,
               "reason" => params["reason"],
               "config" => %{}
             }) do
        finish(socket, result, "Plugin enabled with reviewed permissions.")
      else
        nil -> finish(socket, {:error, :plugin_not_found}, "")
      end
    else
      finish(socket, {:error, :permission_confirmation_required}, "")
    end
  end

  def handle_event("disable", %{"activation_id" => activation_id} = params, socket) do
    if params["confirmed"] == "true" do
      case activation(socket.assigns.plugins, activation_id) do
        nil ->
          finish(socket, {:error, :activation_not_found}, "")

        activation ->
          result =
            Plugins.disable(
              activation.plugin_id,
              activation.scope_type,
              activation.scope_id,
              @actor,
              params["reason"]
            )

          finish(socket, result, "Plugin disabled for the selected scope.")
      end
    else
      finish(socket, {:error, :permission_confirmation_required}, "")
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app>
      <section aria-labelledby="plugins-heading" class="space-y-8">
        <header class="space-y-2">
          <p class="text-sm font-semibold uppercase tracking-wide text-slate-600">Settings</p>
          <h1 id="plugins-heading" class="text-3xl font-semibold tracking-tight text-slate-950">
            Plugins
          </h1>
          <p class="max-w-3xl text-slate-700">
            Discovered plugins remain disabled until you review their manifest, scope, and permissions. Plugin output is always untrusted data.
          </p>
        </header>

        <div class="flex flex-wrap items-center gap-4">
          <button
            type="button"
            phx-click="refresh"
            class="min-h-10 rounded-md border border-slate-400 bg-white px-4 font-medium text-slate-950 focus-visible:outline-2 focus-visible:outline-offset-2"
          >
            Refresh detection
          </button>
          <p role="status" aria-live="polite" class="min-h-6 text-sm text-emerald-900">
            {@notice}
          </p>
        </div>

        <p
          :if={@error != ""}
          role="alert"
          class="rounded-md border border-red-300 bg-red-50 p-3 text-sm text-red-950"
        >
          {@error}
        </p>

        <section
          aria-labelledby="diagnostics-heading"
          class="space-y-4 rounded-lg border border-slate-300 bg-white p-5"
        >
          <div class="space-y-2">
            <h2 id="diagnostics-heading" class="text-xl font-semibold text-slate-950">
              Diagnostics
            </h2>
            <p class="max-w-3xl text-sm text-slate-700">
              Review a private support bundle with versions, allowlisted configuration, migration status, plugin health, power events, normalized error IDs, and aggregate process states.
            </p>
            <p class="max-w-3xl text-sm text-slate-700">
              It excludes source files, worktree contents, prompts, provider output, credentials, raw logs, command output, arguments, environment variables, and private paths.
            </p>
          </div>
          <button
            type="button"
            phx-click="export_diagnostics"
            class="min-h-10 rounded-md border border-slate-400 bg-white px-4 font-medium text-slate-950 focus-visible:outline-2 focus-visible:outline-offset-2"
          >
            Create diagnostics bundle
          </button>
          <p :if={@diagnostics_path} class="break-all text-sm text-slate-700">
            Saved locally: <span class="font-mono">{@diagnostics_path}</span>
          </p>
        </section>

        <p :if={@plugins == []} class="rounded-md border border-slate-300 p-5 text-slate-700">
          No valid plugin manifests were discovered.
        </p>

        <ol :if={@plugins != []} class="space-y-5">
          <li :for={plugin <- @plugins}>
            <article
              id={"plugin-#{plugin.id}"}
              aria-labelledby={"plugin-name-#{plugin.id}"}
              class="space-y-5 rounded-lg border border-slate-300 bg-white p-5"
            >
              <header class="flex flex-wrap items-start justify-between gap-3">
                <div>
                  <p class="text-sm text-slate-600">
                    {plugin.kind} · {plugin.source} · version {plugin.version}
                  </p>
                  <h2 id={"plugin-name-#{plugin.id}"} class="text-xl font-semibold text-slate-950">
                    {plugin.name}
                  </h2>
                </div>
                <span class="rounded-full border border-slate-400 px-3 py-1 text-sm font-medium text-slate-900">
                  Health: {health_label(plugin.health)}
                </span>
              </header>

              <dl class="grid gap-3 text-sm sm:grid-cols-2 lg:grid-cols-4">
                <div>
                  <dt class="font-medium text-slate-700">Network</dt>
                  <dd>{plugin.manifest_json["permissions"]["network"]}</dd>
                </div>
                <div>
                  <dt class="font-medium text-slate-700">Host process</dt>
                  <dd>{yes_no(plugin.manifest_json["permissions"]["host_process"])}</dd>
                </div>
                <div>
                  <dt class="font-medium text-slate-700">Allowed scopes</dt>
                  <dd>{Enum.join(plugin.manifest_json["scopes"], ", ")}</dd>
                </div>
                <div>
                  <dt class="font-medium text-slate-700">Manifest</dt>
                  <dd class="font-mono">{String.slice(plugin.manifest_hash, 0, 12)}</dd>
                </div>
                <div :if={plugin.kind == "runner"}>
                  <dt class="font-medium text-slate-700">Isolation</dt>
                  <dd>
                    {Cuckoding.Plugins.Manifest.isolation_label(
                      plugin.manifest_json["isolation_claims"]
                    )}
                  </dd>
                </div>
              </dl>

              <p
                :if={plugin.last_error}
                class="rounded-md border border-amber-300 bg-amber-50 p-3 text-sm text-amber-950"
              >
                Detection detail: {plugin.last_error}
              </p>

              <section aria-labelledby={"activation-heading-#{plugin.id}"} class="space-y-3">
                <h3 id={"activation-heading-#{plugin.id}"} class="font-semibold text-slate-950">
                  Enabled scopes
                </h3>
                <p :if={plugin.activations == []} class="text-sm text-slate-700">
                  Disabled in every scope.
                </p>
                <ul class="space-y-3">
                  <li
                    :for={activation <- plugin.activations}
                    id={"activation-#{activation.id}"}
                    class="rounded-md border border-slate-200 p-3"
                  >
                    <p class="font-medium text-slate-950">
                      {scope_label(activation)} · {if activation.enabled,
                        do: "Enabled",
                        else: "Disabled"}
                    </p>
                    <p class="text-sm text-slate-700">
                      Network: {activation.network} · approval: {activation.approval_kind} · by {activation.approved_by}
                    </p>
                    <form
                      :if={activation.enabled}
                      phx-submit="disable"
                      class="mt-3 grid gap-3 sm:grid-cols-[minmax(0,1fr)_auto]"
                    >
                      <input type="hidden" name="activation_id" value={activation.id} />
                      <label class="grid gap-1 font-medium text-slate-800">
                        Disable reason
                        <input
                          name="reason"
                          required
                          maxlength="500"
                          class="min-h-10 rounded-md border border-slate-400 px-3 focus-visible:outline-2 focus-visible:outline-offset-2"
                        />
                      </label>
                      <div class="flex flex-col justify-end gap-2">
                        <label class="flex min-h-10 items-center gap-2 text-sm font-medium text-slate-800">
                          <input type="checkbox" name="confirmed" value="true" required />
                          I confirm this scope change
                        </label>
                        <button class="min-h-10 rounded-md border border-slate-500 px-4 font-medium focus-visible:outline-2 focus-visible:outline-offset-2">
                          Disable scope
                        </button>
                      </div>
                    </form>
                  </li>
                </ul>
              </section>

              <form phx-submit="enable" class="space-y-4 rounded-md border border-slate-200 p-4">
                <input type="hidden" name="plugin_id" value={plugin.id} />
                <fieldset class="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
                  <legend class="mb-3 font-semibold text-slate-950">Review and enable a scope</legend>
                  <label class="grid gap-1 font-medium text-slate-800">
                    Scope type
                    <select
                      name="scope_type"
                      class="min-h-10 rounded-md border border-slate-400 bg-white px-3"
                    >
                      <option
                        :for={scope <- ["global" | plugin.manifest_json["scopes"]]}
                        value={scope}
                      >
                        {scope}
                      </option>
                    </select>
                  </label>
                  <label class="grid gap-1 font-medium text-slate-800">
                    Scope ID (empty for global)
                    <input name="scope_id" class="min-h-10 rounded-md border border-slate-400 px-3" />
                  </label>
                  <label class="grid gap-1 font-medium text-slate-800">
                    Network grant
                    <select
                      name="network"
                      class="min-h-10 rounded-md border border-slate-400 bg-white px-3"
                    >
                      <option :for={network <- networks(plugin)} value={network}>{network}</option>
                    </select>
                  </label>
                  <label class="grid gap-1 font-medium text-slate-800">
                    Approval reason
                    <input
                      name="reason"
                      required
                      maxlength="500"
                      class="min-h-10 rounded-md border border-slate-400 px-3"
                    />
                  </label>
                </fieldset>
                <p class="text-sm text-slate-700">
                  Loopback and external access use separate recorded approval paths. Host-runner network limits remain advisory until an enforcing runner is selected.
                </p>
                <label class="flex min-h-10 items-center gap-2 font-medium text-slate-800">
                  <input type="checkbox" name="confirmed" value="true" required />
                  I reviewed this manifest, scope, and network grant
                </label>
                <button
                  disabled={plugin.health != "available"}
                  class="min-h-10 rounded-md bg-slate-950 px-4 font-medium text-white enabled:hover:bg-slate-800 disabled:cursor-not-allowed disabled:opacity-50 focus-visible:outline-2 focus-visible:outline-offset-2"
                >
                  Enable scope
                </button>
              </form>
            </article>
          </li>
        </ol>
      </section>
    </Layouts.app>
    """
  end

  defp load(socket), do: assign(socket, plugins: Plugins.list())

  defp finish(socket, {:ok, _value}, message) do
    {:noreply, socket |> assign(notice: message, error: "") |> load()}
  end

  defp finish(socket, {:error, reason}, _message) do
    {:noreply, assign(socket, notice: "", error: error_message(reason))}
  end

  defp activation(plugins, activation_id) do
    Enum.find_value(plugins, fn plugin ->
      Enum.find(plugin.activations, &(&1.id == activation_id))
    end)
  end

  defp approval_kind("none"), do: "standard"
  defp approval_kind("loopback"), do: "loopback_network"
  defp approval_kind("external"), do: "external_network"
  defp approval_kind(_network), do: "invalid"

  defp networks(plugin) do
    case plugin.manifest_json["permissions"]["network"] do
      "none" -> ["none"]
      "loopback" -> ["none", "loopback"]
      "external" -> ["none", "loopback", "external"]
    end
  end

  defp scope_label(%{scope_type: "global"}), do: "global"
  defp scope_label(activation), do: "#{activation.scope_type}:#{activation.scope_id}"

  defp health_label("available"), do: "Available"
  defp health_label("missing"), do: "Missing binary"
  defp health_label("version_mismatch"), do: "Wrong version"
  defp health_label("unhealthy"), do: "Degraded"
  defp health_label("disabled"), do: "Disabled"

  defp yes_no(true), do: "Allowed"
  defp yes_no(false), do: "Not allowed"

  defp error_message({:disabled_by_parent_scope, scope}), do: "Disabled by #{scope} scope."
  defp error_message(:permission_expansion), do: "The requested scope would expand permissions."

  defp error_message(:network_approval_mismatch),
    do: "The network grant needs its matching approval path."

  defp error_message(:plugin_unavailable), do: "The plugin is not healthy enough to enable."

  defp error_message(:permission_confirmation_required),
    do: "Review and confirm the permission change."

  defp error_message(reason), do: "Plugin change failed: #{inspect(reason)}"
end
