defmodule AgentDeskWeb.WorkspaceHTML do
  @moduledoc false
  use AgentDeskWeb, :html

  import AgentDeskWeb.WorkspacePanels
  import AgentDeskWeb.WorkspaceView

  alias AgentDesk.Branding
  alias AgentDesk.Providers
  alias AgentDeskWeb.Layouts

  def render(assigns) do
    ~H"""
    <div
      id="desk-shell"
      class="desk-shell"
      phx-hook="Shortcuts"
      data-shortcuts={Jason.encode!(@shortcuts)}
    >
      <div id="status-live" class="sr-only" role="status" aria-live="polite" aria-atomic="true">
        {@announce}
      </div>
      <aside class="desk-panel w-80 shrink-0">
        <div class="desk-panel-header">
          <div class="flex min-w-0 items-center gap-3">
            <span class="desk-mark" aria-hidden="true">
              <.icon name="hero-sparkles" class="size-4" />
            </span>
            <div class="min-w-0">
              <p class="desk-title">{Branding.product_name()}</p>
              <p class="desk-muted text-xs">Local multi-agent workspace</p>
            </div>
          </div>
        </div>

        <div class="desk-rule mx-4"></div>

        <section id="open-project" class="desk-section">
          <label class="desk-kicker" for="choose-repo">Open Git repository</label>
          <button
            type="button"
            id="choose-repo"
            phx-hook="RepoPicker"
            phx-click="pick_project_folder"
            class="btn btn-primary btn-sm mt-2 w-full"
            aria-label="Choose repository folder"
          >
            Choose folder…
          </button>
          <.recent_projects
            projects={@recent_projects}
            current_project={@current_project}
            live_project_ids={@live_project_ids}
            confirm_close_project_id={@confirm_close_project_id}
            failed_recent_id={@failed_recent_id}
            confirm_forget_project_id={@confirm_forget_project_id}
          />
          <.onboarding
            :if={@show_onboarding}
            current_project={@current_project}
            provider_status={@provider_status}
            sessions={@sessions}
            search_status={@search_status}
            step={@onboard_step}
            delegation_depth={@delegation_depth}
            xerj_enabled={@xerj_enabled}
          />
        </section>

        <section :if={@current_project} class="desk-scroll desk-section flex-1 pt-0">
          <h2 class="desk-kicker">Project</h2>
          <p class="truncate text-sm font-semibold">{@current_project.name}</p>
          <p class="desk-muted truncate text-xs">
            {@current_project.default_branch || "no branch"} · {@current_project.canonical_path}
          </p>
          <p class="desk-muted mt-2 text-xs">
            {length(@tasks)} tasks · {length(@sessions)} agents · {length(@merge_queue)} handoffs
          </p>
          <div id="sidebar-queues" class="mt-3 space-y-3">
            <div>
              <h3 class="desk-kicker">Tasks</h3>
              <ul id="sidebar-tasks" class="mt-1 space-y-1 text-xs">
                <li :if={@tasks == []} class="desk-empty">No tasks.</li>
                <li :for={item <- sidebar_task_items(@tasks)} class={item.class}>
                  <.status_chip status={item.task.status} /> {item.task.title}
                  <span :if={item.note} class="desk-muted">{[" · ", item.note]}</span>
                </li>
              </ul>
            </div>
            <div>
              <h3 class="desk-kicker">Agents</h3>
              <ul id="sidebar-agents" class="mt-1 space-y-1 text-xs">
                <li :if={@sessions == []} class="desk-empty">No agents yet.</li>
                <li :for={session <- @sessions}>
                  <button
                    type="button"
                    id={"sidebar-agent-#{session.id}"}
                    phx-click="select_tab"
                    phx-value-id={session.id}
                    class={[
                      "desk-nav-item w-full text-left",
                      @workspace_view == "workspace" && @active_session_id == session.id &&
                        "desk-nav-item-active"
                    ]}
                    aria-label={"Open #{session.display_name} tab"}
                  >
                    <.status_chip status={session.status} />
                    {session.display_name}
                  </button>
                </li>
              </ul>
            </div>
            <div>
              <h3 class="desk-kicker">Delegations</h3>
              <ul id="sidebar-delegations" class="mt-1 space-y-1 text-xs">
                <li :if={@delegations == []} class="desk-empty">No delegations.</li>
                <li :if={@delegations != []} class="desk-muted">
                  {length(delegations_with_status(@delegations, "proposed"))} proposed · {length(
                    delegations_with_status(@delegations, "accepted")
                  )} accepted · {length(delegations_with_status(@delegations, "rejected"))} rejected · {length(
                    delegations_with_status(@delegations, "expired")
                  )} expired
                </li>
                <li :for={delegation <- Enum.take(@delegations, 8)}>
                  <.status_chip status={delegation.status} />
                  {delegation.task && delegation.task.title}
                </li>
              </ul>
            </div>
            <div>
              <h3 class="desk-kicker">Files</h3>
              <ul id="sidebar-worktrees" class="mt-1 space-y-1 text-xs">
                <li :if={@worktrees == []} class="desk-empty">No worktrees.</li>
                <li :for={tree <- Enum.take(@worktrees, 8)}>
                  {tree.branch_name} · {tree.status}
                </li>
              </ul>
            </div>
            <div>
              <h3 class="desk-kicker">Handoffs</h3>
              <ul id="sidebar-handoffs" class="mt-1 space-y-1 text-xs">
                <li :if={@merge_queue == []} class="desk-empty">No handoffs.</li>
                <li :for={item <- Enum.take(@merge_queue, 8)}>
                  <button
                    type="button"
                    phx-click="review_handoff"
                    phx-value-id={item.id}
                    class="text-left"
                  >
                    <.status_chip status={item.status} /> {item.summary}
                  </button>
                </li>
              </ul>
            </div>
            <form id="sidebar-search" phx-submit="search_project" class="space-y-1">
              <label class="desk-kicker" for="sidebar-search-q">Search</label>
              <input
                id="sidebar-search-q"
                name="q"
                value={@search_query}
                class="input input-bordered input-xs w-full"
                placeholder="Search project"
                aria-label="Search project from sidebar"
              />
            </form>
          </div>
          <nav id="sidebar-nav" class="mt-3 flex flex-wrap gap-1" aria-label="Project areas">
            <a href="#task-conversation" class="desk-filter">Tasks</a>
            <a href="#agents-directory" class="desk-filter">Agents</a>
            <a href="#worktree-panel" class="desk-filter">Files</a>
            <a href="#artifact-panel" class="desk-filter">Artifacts</a>
            <a href="#merge-queue" class="desk-filter">Handoffs</a>
            <a href="#search-panel" class="desk-filter">Search</a>
            <a href="#provider-diagnostics" class="desk-filter">Diagnostics</a>
            <a href="#shortcuts-help" class="desk-filter">Settings</a>
            <button
              type="button"
              id="view-registry"
              phx-click="set_view"
              phx-value-view="registry"
              class="desk-filter"
            >
              ACP Registry
            </button>
          </nav>
        </section>

        <details id="shortcuts-help" class="desk-details desk-section pt-0">
          <summary>Settings · shortcuts</summary>
          <form id="shortcut-form" phx-submit="save_shortcuts" class="mt-2 space-y-1 text-xs">
            <div
              :for={{key, combo} <- @shortcuts}
              class="flex items-center justify-between gap-2"
            >
              <span>{key}</span>
              <input name={key} value={combo} class="input input-bordered input-xs w-36" />
            </div>
            <.button class="btn btn-xs">Save shortcuts</.button>
          </form>
        </details>
      </aside>

      <main class="desk-panel min-w-0 flex-1">
        <header class="desk-panel-header">
          <div class="min-w-0">
            <h1 class="desk-title text-xl">
              {if @current_project, do: @current_project.name, else: "No project open"}
            </h1>
            <p class="desk-muted mt-1 text-xs">
              {cond do
                is_nil(@current_project) ->
                  "Open a Git repository to start concurrent agent sessions."

                is_binary(@current_project.default_branch) and @current_project.default_branch != "" ->
                  "#{@current_project.canonical_path} · #{@current_project.default_branch}"

                true ->
                  @current_project.canonical_path
              end}
            </p>
          </div>
        </header>

        <div class="desk-rule mx-5"></div>

        <div
          :if={@current_project}
          id="session-tabs"
          class="desk-tab-row"
          role="tablist"
          aria-label="Workspace tabs"
        >
          <button
            type="button"
            id="tab-dashboard"
            phx-click="set_view"
            phx-value-view="dashboard"
            role="tab"
            aria-selected={to_string(@workspace_view == "dashboard")}
            class={[
              "desk-tab desk-tab-pinned",
              @workspace_view == "dashboard" && "desk-tab-active"
            ]}
          >
            <span class="desk-tab-title">Dashboard</span>
          </button>
          <div id="session-tab-scroll" class="desk-tab-scroll">
            <div
              :for={session <- @sessions}
              class={[
                "desk-tab-group",
                @workspace_view == "workspace" && @active_session_id == session.id &&
                  "desk-tab-group-active"
              ]}
            >
              <button
                type="button"
                id={"tab-#{session.id}"}
                phx-click="select_tab"
                phx-value-id={session.id}
                role="tab"
                aria-selected={
                  to_string(@workspace_view == "workspace" and @active_session_id == session.id)
                }
                aria-label={"#{tab_label(session, @sessions)}, #{session.status}"}
                title={"#{tab_label(session, @sessions)} · #{session.status}"}
                class={[
                  "desk-tab",
                  @workspace_view == "workspace" && @active_session_id == session.id &&
                    "desk-tab-active"
                ]}
              >
                <span class={["desk-tab-dot", status_tone(session.status)]} aria-hidden="true"></span>
                <span class="desk-tab-title">{tab_label(session, @sessions)}</span>
                <span :if={Map.get(@unread, session.id, 0) > 0} class="desk-tab-unread">
                  {Map.get(@unread, session.id, 0)}
                </span>
              </button>
              <button
                type="button"
                id={"close-tab-#{session.id}"}
                phx-click="close_tab"
                phx-value-id={session.id}
                class="desk-tab-close"
                title="Close tab without terminating"
                aria-label={"Close #{session.display_name}"}
              >
                ×
              </button>
            </div>
          </div>
          <button
            type="button"
            id="tab-new"
            phx-click="set_view"
            phx-value-view="new"
            role="tab"
            aria-selected={to_string(@workspace_view == "new")}
            class={[
              "desk-tab desk-tab-new",
              @workspace_view == "new" && "desk-tab-active"
            ]}
            aria-label="New agent tab"
            title="New agent tab"
          >
            +
          </button>
        </div>

        <div class="desk-workspace">
          <section class="flex h-full min-h-0 flex-col">
            <.registry
              :if={@workspace_view == "registry"}
              query={@registry_query}
              filter={@registry_filter}
              agents={@registry_agents}
              docs_url={Branding.registry_docs_url()}
            />
            <.analytics :if={@workspace_view == "dashboard"} report={@analytics} />
            <div
              :if={@workspace_view == "handoff"}
              id="handoff-review"
              class="desk-scroll min-h-0 flex-1 p-5"
            >
              <header class="mb-4 flex items-start justify-between gap-3">
                <div>
                  <p class="desk-kicker">Handoff review</p>
                  <h2 class="desk-title text-xl">
                    {(@review_item && @review_item.summary) || "No handoff selected"}
                  </h2>
                </div>
                <button
                  type="button"
                  phx-click="set_view"
                  phx-value-view="workspace"
                  class="btn btn-ghost btn-sm"
                >
                  Back to workspace
                </button>
              </header>
              <p :if={@merge_queue == []} class="desk-empty">No handoffs waiting.</p>
              <div :if={@review_item} class="desk-card-stack max-w-3xl space-y-3">
                <p class="flex flex-wrap items-center gap-2">
                  <.status_chip status={@review_item.status} />
                  <.status_chip status={@review_item.policy_status} />
                </p>
                <p class="desk-muted text-sm">
                  {@review_item.branch_name} → {@review_item.target_ref}
                  <span :if={@review_item.commit_sha}>· {short_sha(@review_item.commit_sha)}</span>
                </p>
                <p :if={handoff_commits(@review_item, @worktrees, @artifacts)} class="text-sm">
                  base {short_sha(elem(handoff_commits(@review_item, @worktrees, @artifacts), 0))} → head {short_sha(
                    elem(handoff_commits(@review_item, @worktrees, @artifacts), 1)
                  )}
                </p>
                <p :if={handoff_files(@artifacts, @review_item) != []} class="text-sm">
                  {length(handoff_files(@artifacts, @review_item))} files · {Enum.join(
                    handoff_files(@artifacts, @review_item),
                    ", "
                  )}
                </p>
                <p :if={handoff_checks(@artifacts, @review_item) != []} class="text-sm">
                  checks {Enum.join(handoff_checks(@artifacts, @review_item), ", ")}
                </p>
                <p :if={policy_summary(@review_item)} class="text-warning text-sm">
                  {policy_summary(@review_item)}
                </p>
                <p :if={handoff_warnings(@artifacts, @review_item) != []} class="text-warning text-sm">
                  {Enum.join(handoff_warnings(@artifacts, @review_item), ", ")}
                </p>
                <p :if={handoff_artifact(@artifacts, @review_item)} class="desk-muted text-xs">
                  artifact {short_sha(handoff_artifact(@artifacts, @review_item).id)}
                  <span :if={handoff_artifact(@artifacts, @review_item).context_id}>
                    · context {short_sha(handoff_artifact(@artifacts, @review_item).context_id)}
                  </span>
                  <span :if={handoff_artifact(@artifacts, @review_item).task_id}>
                    · task {short_sha(handoff_artifact(@artifacts, @review_item).task_id)}
                  </span>
                </p>
                <p
                  :if={handoff_held_leases(@leases, @review_item) != []}
                  class="text-warning text-sm"
                >
                  still holding {Enum.join(
                    Enum.map(handoff_held_leases(@leases, @review_item), & &1.resource_key),
                    ", "
                  )}
                </p>
                <div
                  :if={handoff_review_messages(@messages, @artifacts, @review_item) != []}
                  class="space-y-1"
                >
                  <p class="desk-kicker">Review conversation</p>
                  <p
                    :for={message <- handoff_review_messages(@messages, @artifacts, @review_item)}
                    class="text-sm"
                  >
                    {message.kind} · {message.body}
                  </p>
                </div>
                <p :if={merge_blocked?(@review_item, @worktrees)} class="text-warning text-sm">
                  Integration is disabled until checks pass and Git is conflict-free.
                </p>
                <div class="flex flex-wrap gap-1 pt-1">
                  <button
                    :if={@review_item.status == "queued"}
                    type="button"
                    phx-click="accept_queue_item"
                    phx-value-artifact_id={@review_item.artifact_id}
                    class="btn btn-sm"
                  >
                    Accept
                  </button>
                  <button
                    :if={@review_item.status in ["queued", "accepted"]}
                    type="button"
                    phx-click="reject_queue_item"
                    phx-value-artifact_id={@review_item.artifact_id}
                    class="btn btn-sm"
                  >
                    Reject
                  </button>
                  <button
                    :if={
                      @review_item.status == "accepted" and
                        not merge_blocked?(@review_item, @worktrees) and
                        @confirm_merge_id != @review_item.id
                    }
                    type="button"
                    id={"handoff-confirm-merge-#{@review_item.id}"}
                    phx-click="confirm_merge"
                    phx-value-id={@review_item.id}
                    class="btn btn-sm"
                  >
                    Merge
                  </button>
                  <button
                    :if={@confirm_merge_id == @review_item.id}
                    type="button"
                    id={"handoff-merge-#{@review_item.id}"}
                    phx-click="merge_queue_item"
                    phx-value-id={@review_item.id}
                    class="btn btn-sm btn-error"
                  >
                    Confirm merge
                  </button>
                  <button
                    :if={@confirm_merge_id == @review_item.id}
                    type="button"
                    phx-click="cancel_merge"
                    class="btn btn-sm"
                  >
                    Cancel
                  </button>
                </div>
              </div>
            </div>
            <div :if={@workspace_view == "new"} class="flex h-full min-h-0 flex-col">
              <div :if={@current_project} class="desk-section pb-2">
                <form
                  id="start-session-form"
                  phx-change="session_form"
                  phx-submit="start_session"
                  class="desk-toolbar"
                >
                  <label class="desk-field">
                    <span class="desk-kicker mb-0">Provider</span>
                    <select name="provider" class="select select-bordered select-sm">
                      <option
                        :for={key <- Providers.ui_keys()}
                        value={key}
                        selected={key == @provider}
                      >
                        {Providers.ui_label(key)}{provider_ready_mark(@provider_status, key)}
                      </option>
                    </select>
                  </label>
                  <label class="desk-field min-w-40 flex-1">
                    <span class="desk-kicker mb-0">Session</span>
                    <input
                      type="text"
                      name="display_name"
                      value={@display_name}
                      placeholder="Name this tab"
                      class="input input-bordered input-sm w-full"
                    />
                  </label>
                  <.button id="new-session" class="btn btn-primary btn-sm">New session</.button>
                  <details class="desk-details">
                    <summary>Role & isolation</summary>
                    <div class="desk-toolbar mt-2">
                      <label class="desk-field">
                        <span class="desk-kicker mb-0">Role</span>
                        <select
                          name="role_id"
                          id="session-role"
                          class="select select-bordered select-sm"
                        >
                          <option value="">None</option>
                          <option :for={role <- @roles} value={role.id}>{role.name}</option>
                        </select>
                      </label>
                      <input
                        :if={@provider == "sdk"}
                        type="text"
                        name="sdk_executable"
                        id="sdk-executable"
                        value={@sdk_executable}
                        placeholder="SDK executable"
                        class="input input-bordered input-sm"
                      />
                      <input
                        :if={@provider == "sdk"}
                        type="text"
                        name="sdk_args"
                        id="sdk-args"
                        value={@sdk_args}
                        placeholder="one arg per line"
                        class="input input-bordered input-sm"
                      />
                      <label class="desk-muted flex items-center gap-2 text-xs">
                        <input
                          type="checkbox"
                          name="container"
                          value="true"
                          id="container-opt-in"
                          class="checkbox checkbox-sm"
                        /> Isolated Compose
                      </label>
                      <label class="desk-muted flex items-center gap-2 text-xs">
                        <input
                          type="checkbox"
                          name="shared"
                          value="true"
                          id="shared-opt-in"
                          class="checkbox checkbox-sm"
                        /> Shared primary tree
                      </label>
                    </div>
                  </details>
                </form>
                <details class="desk-details mt-2">
                  <summary>Save a role</summary>
                  <form id="save-role-form" phx-submit="save_role" class="desk-toolbar mt-2">
                    <input
                      type="text"
                      name="name"
                      placeholder="Role name"
                      class="input input-bordered input-sm"
                    />
                    <input
                      type="text"
                      name="description"
                      placeholder="Safe card description"
                      class="input input-bordered input-sm"
                    />
                    <select name="permission_profile" class="select select-bordered select-sm">
                      <option value="default">default</option>
                      <option value="observer">observer</option>
                      <option value="restricted">restricted</option>
                    </select>
                    <input
                      type="text"
                      name="prompt"
                      placeholder="Session prompt (never published)"
                      class="input input-bordered input-sm w-64"
                    />
                    <.button class="btn btn-ghost btn-sm">Save role</.button>
                  </form>
                </details>
              </div>
            </div>
            <div :if={@workspace_view == "workspace"} class="flex h-full min-h-0 flex-col">
              <div
                :if={@active_session_id == nil}
                class="desk-empty-hero"
              >
                <p class="desk-title text-lg">Ready when you are</p>
                <p class="desk-muted mt-2 max-w-md text-sm">
                  Open a Git repository, then start Codex, Claude, Cursor, or OpenCode. Each session gets its own tab and isolated worktree.
                </p>
              </div>
              <div :if={@active} class="desk-stream-toolbar">
                <p class="desk-muted text-xs">
                  Latest {@activity_limit} activity cards
                  <button
                    :if={@activity_older?}
                    type="button"
                    id="load-older-activity"
                    phx-click="load_older_activity"
                    class="btn btn-ghost btn-xs ml-2"
                  >
                    Load older
                  </button>
                </p>
                <div class="flex flex-wrap gap-1">
                  <button
                    type="button"
                    id="activity-cards"
                    phx-click="set_activity_mode"
                    phx-value-mode="cards"
                    class={["btn btn-ghost btn-xs", @activity_mode == "cards" && "btn-active"]}
                  >
                    Cards
                  </button>
                  <button
                    type="button"
                    id="activity-raw"
                    phx-click="set_activity_mode"
                    phx-value-mode="raw"
                    class={["btn btn-ghost btn-xs", @activity_mode == "raw" && "btn-active"]}
                  >
                    Raw
                  </button>
                  <button
                    type="button"
                    phx-click="set_type_scale"
                    phx-value-scale="sm"
                    class={["btn btn-ghost btn-xs", @type_scale == "sm" && "btn-active"]}
                    aria-label="Smaller activity text"
                  >
                    A−
                  </button>
                  <button
                    type="button"
                    phx-click="set_type_scale"
                    phx-value-scale="md"
                    class={["btn btn-ghost btn-xs", @type_scale == "md" && "btn-active"]}
                    aria-label="Default activity text"
                  >
                    A
                  </button>
                  <button
                    type="button"
                    phx-click="set_type_scale"
                    phx-value-scale="lg"
                    class={["btn btn-ghost btn-xs", @type_scale == "lg" && "btn-active"]}
                    aria-label="Larger activity text"
                  >
                    A+
                  </button>
                </div>
              </div>
              <div class="relative min-h-0 flex-1">
                <div
                  :if={@active}
                  id="activity-load-sentinel"
                  phx-hook="LoadOlder"
                  data-older={to_string(@activity_older?)}
                  class="pointer-events-none absolute inset-x-0 top-0 h-1"
                >
                </div>
                <div
                  id="activity-stream"
                  phx-update="stream"
                  class={[
                    "desk-scroll h-full min-h-0 px-5 py-3 text-sm",
                    "desk-type-#{@type_scale}"
                  ]}
                >
                  <.activity_card
                    :for={{dom_id, item} <- @streams.activity}
                    dom_id={dom_id}
                    item={item}
                    mode={@activity_mode}
                  />
                </div>
              </div>

              <div :if={@active} class="desk-composer">
                <p :if={@connect_path} id="remote-connect" class="desk-muted mb-2 break-all text-xs">
                  Connect file: {@connect_path}
                </p>
                <div class="mb-3 flex flex-wrap gap-2">
                  <button
                    :if={@active_status in ["queued", "starting"]}
                    type="button"
                    id="cancel-session"
                    phx-click="terminate"
                    class="btn btn-ghost btn-sm"
                  >
                    Cancel
                  </button>
                  <button
                    :if={
                      @active_status in ["working", "waiting"] or
                        (@caps && @caps.steer_active_turn &&
                           @active_status not in ["queued", "starting", "terminated", "completed"])
                    }
                    type="button"
                    id="interrupt-session"
                    phx-click="interrupt"
                    class="btn btn-warning btn-sm"
                  >
                    Interrupt
                  </button>
                  <button
                    :if={@active_status == "working" && @caps && @caps.steer_active_turn}
                    type="button"
                    id="steer-session"
                    phx-click={JS.focus(to: "#prompt-composer textarea")}
                    class="btn btn-sm"
                  >
                    Steer
                  </button>
                  <button
                    :if={@active_status in ["interrupted", "failed"] && @caps && @caps.resume}
                    type="button"
                    id="resume-session"
                    phx-click="resume_session"
                    phx-value-id={@active.id}
                    class="btn btn-sm"
                  >
                    Resume
                  </button>
                  <a
                    :if={@active_status == "blocked"}
                    href="#resource-leases"
                    id="resolve-conflict"
                    class="btn btn-sm"
                  >
                    Resolve conflict
                  </a>
                  <button
                    :if={@active_status == "blocked" && blocked_lease_id(@lease_previews)}
                    type="button"
                    phx-click="lease_message"
                    phx-value-id={blocked_lease_id(@lease_previews)}
                    class="btn btn-sm"
                  >
                    Message owner
                  </button>
                  <button
                    :if={@active_status == "blocked"}
                    type="button"
                    phx-click="lease_other_task"
                    class="btn btn-sm"
                  >
                    Reassign
                  </button>
                  <a
                    :if={@active_status == "failed"}
                    href="#provider-diagnostics"
                    id="view-diagnostics"
                    class="btn btn-sm"
                  >
                    View diagnostics
                  </a>
                  <button
                    :if={@active_status == "failed"}
                    type="button"
                    id="retry-session"
                    phx-click="retry_session"
                    class="btn btn-sm"
                  >
                    Retry
                  </button>
                  <button
                    :if={@active_status == "completed"}
                    type="button"
                    class="btn btn-sm"
                    id="review-handoff"
                    phx-click="review_handoff"
                  >
                    Review handoff
                  </button>
                  <button
                    :if={@active_status == "completed"}
                    type="button"
                    id="continue-session"
                    phx-click={JS.focus(to: "#prompt-composer textarea")}
                    class="btn btn-sm"
                  >
                    Continue
                  </button>
                  <button
                    :if={@active_status == "terminated"}
                    type="button"
                    id="archive-session"
                    phx-click="close_tab"
                    phx-value-id={@active.id}
                    class="btn btn-ghost btn-sm"
                  >
                    Archive
                  </button>
                  <button
                    :if={
                      @active_status not in ["terminated", "queued", "starting", "terminating"] and
                        !@confirm_terminate
                    }
                    type="button"
                    id="confirm-terminate"
                    phx-click="confirm_terminate"
                    class="btn btn-error btn-sm"
                  >
                    Terminate
                  </button>
                  <button
                    :if={
                      @active_status == "terminating" and @allow_force_terminate and
                        !@confirm_terminate
                    }
                    type="button"
                    id="force-terminate"
                    phx-click="confirm_terminate"
                    class="btn btn-error btn-sm"
                  >
                    Force terminate
                  </button>
                  <button
                    :if={@confirm_terminate}
                    type="button"
                    id="terminate-session"
                    phx-click="terminate"
                    class="btn btn-error btn-sm"
                  >
                    Confirm terminate
                  </button>
                  <button
                    :if={@confirm_terminate}
                    type="button"
                    phx-click="cancel_terminate"
                    class="btn btn-ghost btn-sm"
                  >
                    Cancel
                  </button>
                </div>
                <p :if={@active_status == "terminating"} class="desk-muted mb-2 text-xs">
                  Wait for the session to exit. Force terminate is available if it hangs.
                </p>
                <form
                  id="prompt-composer"
                  phx-submit="send_prompt"
                  phx-change="validate_prompt"
                  phx-hook="Composer"
                  data-send-shortcut={@shortcuts["send"]}
                  class="desk-composer-form"
                >
                  <div
                    :if={@uploads.attachments.entries != []}
                    class="desk-composer-files"
                    id="prompt-attachments"
                  >
                    <span
                      :for={entry <- @uploads.attachments.entries}
                      id={"attach-#{entry.ref}"}
                      class="desk-composer-file"
                    >
                      <span class="truncate">{entry.client_name}</span>
                      <button
                        type="button"
                        id={"remove-attach-#{entry.ref}"}
                        phx-click="cancel_attachment"
                        phx-value-ref={entry.ref}
                        aria-label={"Remove #{entry.client_name}"}
                      >
                        ×
                      </button>
                    </span>
                  </div>
                  <p
                    :for={err <- upload_errors(@uploads.attachments)}
                    class="text-error mb-2 text-xs"
                  >
                    {upload_error_text(err)}
                  </p>
                  <div class="flex items-end gap-3">
                    <label class="btn btn-ghost btn-sm shrink-0" title="Attach files or images">
                      Attach <.live_file_input upload={@uploads.attachments} class="sr-only" />
                    </label>
                    <textarea
                      name="prompt"
                      class="textarea textarea-bordered textarea-sm min-h-16 flex-1"
                      placeholder={
                        if @active_status == "working" && @caps && @caps.steer_active_turn,
                          do: "Steer this turn. Paste or drop images.",
                          else: "Send a prompt. Paste or drop images and files."
                      }
                      aria-label="Prompt"
                    >{@prompt}</textarea>
                    <.button class="btn btn-primary">Send</.button>
                  </div>
                </form>
                <p class="desk-muted mt-2 text-xs">
                  {@shortcuts["send"]} sends. Paste or drop images like Cursor. Shortcuts are listed under Settings.
                </p>
              </div>
            </div>
          </section>

          <aside class="desk-context desk-scroll p-4">
            <h2 class="desk-kicker">Context</h2>
            <.grove sessions={@sessions} />
            <div class="desk-card-stack">
              <.context_card title="Runtime">
                {cond do
                  is_nil(@current_project) ->
                    "Idle"

                  is_binary(@current_project.default_branch) and @current_project.default_branch != "" ->
                    "Runtime started · #{@current_project.default_branch}"

                  true ->
                    "Project runtime started"
                end}
              </.context_card>

              <.context_card title="Session">
                <div id="session-status" class="flex flex-wrap items-center gap-2">
                  <span :if={!@active} class="desk-empty">No active tab</span>
                  <span :if={@active}>
                    {Providers.ui_label(@active.provider)} · {@active.display_name}
                  </span>
                  <.status_chip :if={@active} status={@active_status} />
                  <span
                    :if={@active && @active.started_at}
                    id={"elapsed-#{@active.id}"}
                    class="desk-muted text-xs"
                    phx-hook="Elapsed"
                    data-started-at={DateTime.to_iso8601(@active.started_at)}
                  >
                  </span>
                </div>
                <p :if={@active && session_model(@active)} class="desk-muted mt-1 text-xs">
                  {session_model(@active)}
                </p>
                <p :if={@active_worktree} class="desk-muted mt-1 text-xs">
                  {@active_worktree.branch_name} · {@active_worktree.status}
                </p>
                <p
                  :if={@active && @active.started_at}
                  id="session-elapsed"
                  class="desk-muted mt-1 text-xs"
                  phx-hook="Elapsed"
                  data-started-at={DateTime.to_iso8601(@active.started_at)}
                >
                </p>
              </.context_card>

              <.context_card title="Provider">
                <div id="provider-diagnostics">
                  <p :if={!@active} class="desk-empty">No active tab</p>
                  <p :if={@active}>
                    {Providers.ui_label(@active.provider)}
                    <span :if={@active.provider_version}>· {@active.provider_version}</span>
                  </p>
                  <p :if={@caps} class="desk-muted text-xs">
                    steer {yesno(@caps.steer_active_turn)} · resume {yesno(@caps.resume)} · approvals {yesno(
                      @caps.approvals
                    )}
                  </p>
                  <p
                    :if={match?(%{available: true}, @provider_status[@active && @active.provider])}
                    class="desk-muted text-xs"
                  >
                    {@provider_status[@active.provider][:executable]}
                  </p>
                </div>
              </.context_card>

              <.context_card :if={@isolation} title="Isolation">
                <div id="isolation-card" class="space-y-1 text-xs">
                  <p>db {@isolation["database"]}</p>
                  <p>schema {@isolation["schema"]}</p>
                  <p>partition {@isolation["partition"]}</p>
                  <p>compose {@isolation["compose_project"]}</p>
                  <p :if={@isolation["port"]} class="desk-muted">
                    port {@isolation["port"]} · bind 127.0.0.1
                  </p>
                  <p class="desk-muted truncate" title={@isolation["dir"]}>
                    {@isolation["dir"]}
                  </p>
                </div>
              </.context_card>

              <.context_card :if={@pending_approval} title="Approval">
                <div id="approval-card" class="desk-approval space-y-2">
                  <p>
                    {@pending_approval.payload["action"]} — {@pending_approval.payload["summary"]}
                  </p>
                  <div class="flex gap-2">
                    <button
                      type="button"
                      id="approve-request"
                      phx-click="approve"
                      phx-value-id={@pending_approval.payload["request_id"]}
                      class="btn btn-success btn-xs"
                    >
                      Allow
                    </button>
                    <button
                      type="button"
                      id="deny-request"
                      phx-click="deny"
                      phx-value-id={@pending_approval.payload["request_id"]}
                      class="btn btn-error btn-xs"
                    >
                      Deny
                    </button>
                  </div>
                </div>
              </.context_card>

              <.context_card title="Agents">
                <div id="agents-directory">
                  <div id="agent-filters" class="mb-2 flex flex-wrap gap-1">
                    <button
                      type="button"
                      id="agent-filter-all"
                      phx-click="filter_agents"
                      phx-value-filter="all"
                      class={["desk-filter", @agent_filter == "all" && "desk-filter-active"]}
                    >
                      All
                    </button>
                    <button
                      :for={key <- agent_filter_keys(@agents)}
                      type="button"
                      id={"agent-filter-#{filter_dom_id(key)}"}
                      phx-click="filter_agents"
                      phx-value-filter={key}
                      class={["desk-filter", @agent_filter == key && "desk-filter-active"]}
                    >
                      {key}
                    </button>
                  </div>
                  <p :if={visible_agents(@agents, @agent_filter) == []} class="desk-empty">
                    No Agent Cards yet.
                  </p>
                  <div
                    :for={card <- visible_agents(@agents, @agent_filter)}
                    id={"agent-card-#{card.agent_id}"}
                    class="mb-3"
                  >
                    <p class="font-semibold">
                      <button
                        type="button"
                        id={"open-agent-#{card.agent_id}"}
                        phx-click="select_tab"
                        phx-value-id={card.agent_id}
                        class="text-left"
                      >
                        {card.name}
                      </button>
                    </p>
                    <p class="desk-muted text-xs">
                      {card.availability}
                      <span :if={session_for_card(@sessions, card.agent_id)}>
                        · {Providers.ui_label(session_for_card(@sessions, card.agent_id).provider)}
                        <span :if={session_for_card(@sessions, card.agent_id).role}>
                          · {session_for_card(@sessions, card.agent_id).role}
                        </span>
                      </span>
                      <span :if={card.description not in [nil, ""]}>· {card.description}</span>
                    </p>
                    <p class="desk-muted text-xs">{card_load_summary(card, @sessions, @tasks)}</p>
                    <p
                      :if={
                        session_for_card(@sessions, card.agent_id) &&
                          session_for_card(@sessions, card.agent_id).last_heartbeat_at
                      }
                      class="desk-muted text-xs"
                    >
                      heartbeat {Calendar.strftime(
                        session_for_card(@sessions, card.agent_id).last_heartbeat_at,
                        "%H:%M:%S"
                      )}
                    </p>
                    <p :if={skill_names(card.skills) != []} class="mt-1 flex flex-wrap gap-1">
                      <span :for={skill <- skill_names(card.skills)} class="desk-skill">{skill}</span>
                    </p>
                    <p :if={feature_names(card.features) != []} class="mt-1 flex flex-wrap gap-1">
                      <span :for={feature <- feature_names(card.features)} class="desk-chip">
                        {feature}
                      </span>
                    </p>
                    <p
                      :if={card.input_modes != [] or card.output_modes != []}
                      class="desk-muted mt-1 text-xs"
                    >
                      in {Enum.join(card.input_modes || [], ", ")} · out {Enum.join(
                        card.output_modes || [],
                        ", "
                      )}
                    </p>
                    <div class="desk-agent-actions">
                      <button
                        type="button"
                        phx-click="message_agent"
                        phx-value-id={card.agent_id}
                        class="btn btn-xs"
                      >
                        Message
                      </button>
                      <button
                        type="button"
                        phx-click="delegate_agent"
                        phx-value-id={card.agent_id}
                        class="btn btn-xs"
                      >
                        Delegate task
                      </button>
                      <button
                        type="button"
                        phx-click="request_review"
                        phx-value-id={card.agent_id}
                        class="btn btn-xs"
                      >
                        Request review
                      </button>
                    </div>
                  </div>
                </div>
              </.context_card>

              <.context_card title="Delegations">
                <div id="delegation-inbox">
                  <p :if={@delegations == []} class="desk-empty">No delegations yet.</p>
                  <div
                    :for={delegation <- @delegations}
                    class="mb-3 space-y-1"
                  >
                    <p class="flex flex-wrap items-center gap-2">
                      <.status_chip status={delegation.status} />
                      <span>{delegation.task && delegation.task.title}</span>
                    </p>
                    <p class="desk-muted text-xs">
                      {session_name(@sessions, delegation.from_agent_id)} → {session_name(
                        @sessions,
                        delegation.to_agent_id
                      )}
                      <span :if={delegation.reason}>· {delegation.reason}</span>
                    </p>
                    <p
                      :if={delegation_skills(delegation) != []}
                      class="desk-muted text-xs"
                    >
                      skills {Enum.join(delegation_skills(delegation), ", ")}
                    </p>
                    <p :if={delegation.response_reason} class="desk-muted text-xs">
                      response {delegation.response_reason}
                    </p>
                    <p :if={delegation.context_id} class="desk-muted text-xs">
                      context {delegation.context_id}
                    </p>
                    <p :if={delegation.expires_at} class="desk-muted text-xs">
                      expires
                      <span
                        phx-hook="Elapsed"
                        id={"delegation-expiry-#{delegation.id}"}
                        data-until={DateTime.to_iso8601(delegation.expires_at)}
                      >
                      </span>
                    </p>
                    <div class="flex flex-wrap items-center gap-1">
                      <button
                        :if={delegation.status == "proposed"}
                        type="button"
                        phx-click="accept_delegation"
                        phx-value-id={delegation.id}
                        class="btn btn-xs"
                      >
                        Accept
                      </button>
                      <form
                        :if={delegation.status == "proposed"}
                        phx-submit="reject_delegation"
                        class="flex flex-wrap gap-1"
                      >
                        <input type="hidden" name="delegation_id" value={delegation.id} />
                        <input
                          name="reason"
                          class="input input-bordered input-xs w-28"
                          placeholder="Reject with reason"
                        />
                        <.button class="btn btn-xs">Reject</.button>
                      </form>
                      <button
                        :if={delegation.status == "proposed"}
                        type="button"
                        phx-click="revoke_delegation"
                        phx-value-id={delegation.id}
                        class="btn btn-xs"
                      >
                        Revoke
                      </button>
                    </div>
                    <form
                      :if={delegation.status == "proposed" and length(@sessions) > 1}
                      phx-submit="redirect_delegation"
                      class="mt-1 flex flex-wrap gap-1"
                    >
                      <input type="hidden" name="delegation_id" value={delegation.id} />
                      <select name="to_agent_id" class="select select-bordered select-xs">
                        <option
                          :for={session <- @sessions}
                          :if={session.id != delegation.to_agent_id}
                          value={session.id}
                        >
                          {session.display_name}
                        </option>
                      </select>
                      <.button class="btn btn-xs">Redirect</.button>
                    </form>
                  </div>
                </div>
              </.context_card>

              <.context_card title="Leases">
                <div id="resource-leases">
                  <p :if={@lease_previews == []} class="desk-empty">No active leases.</p>
                  <div
                    :for={{lease, overlaps} <- @lease_previews}
                    id={"lease-#{lease.id}"}
                    class="mb-3"
                  >
                    <p>
                      {lease.mode} {lease.resource_type}:{lease.resource_key}
                    </p>
                    <p class="desk-muted text-xs">
                      {session_name(@sessions, lease.agent_session_id)} · {lease.reason} · expires
                      <span
                        :if={lease.expires_at}
                        id={"lease-expiry-#{lease.id}"}
                        phx-hook="Elapsed"
                        data-until={DateTime.to_iso8601(lease.expires_at)}
                      >
                      </span>
                    </p>
                    <p :if={match?([_ | _], overlaps)} class="text-warning text-xs">
                      overlaps {Enum.join(overlaps, ", ")}
                    </p>
                    <div :if={match?([_ | _], overlaps)} class="desk-lease-actions">
                      <button
                        type="button"
                        phx-click="lease_message"
                        phx-value-id={lease.id}
                        class="btn btn-xs"
                      >
                        Send message
                      </button>
                      <button type="button" phx-click="lease_wait" class="btn btn-xs">
                        Wait and retry
                      </button>
                      <button type="button" phx-click="lease_other_task" class="btn btn-xs">
                        Choose another task
                      </button>
                      <button
                        type="button"
                        phx-click="request_lease_release"
                        phx-value-id={lease.id}
                        class="btn btn-xs"
                      >
                        Request release
                      </button>
                      <button
                        :if={@confirm_revoke_lease_id != lease.id}
                        type="button"
                        phx-click="confirm_revoke_lease"
                        phx-value-id={lease.id}
                        class="btn btn-xs btn-error"
                      >
                        Revoke
                      </button>
                      <button
                        :if={@confirm_revoke_lease_id == lease.id}
                        type="button"
                        id={"confirm-revoke-lease-#{lease.id}"}
                        phx-click="revoke_lease"
                        phx-value-id={lease.id}
                        class="btn btn-xs btn-error"
                      >
                        Confirm revoke
                      </button>
                      <button
                        :if={@confirm_revoke_lease_id == lease.id}
                        type="button"
                        phx-click="cancel_revoke_lease"
                        class="btn btn-xs"
                      >
                        Cancel
                      </button>
                    </div>
                  </div>
                </div>
              </.context_card>

              <.context_card title="Tasks">
                <div id="task-conversation">
                  <p :if={@tasks == []} class="desk-empty">No tasks yet.</p>
                  <div
                    :for={node <- task_forest(@tasks)}
                    id={"task-group-#{node.task.id}"}
                    class="mb-3"
                  >
                    <.task_item task={node.task} task_deps={@task_deps} />
                    <p :if={crew_progress(node.task, node.children)} class="desk-muted mt-1 text-xs">
                      {crew_progress(node.task, node.children)}
                    </p>
                    <div
                      :if={node.children != []}
                      class="mt-1 ml-2 space-y-1 border-l border-white/10 pl-3"
                    >
                      <.task_item
                        :for={child <- node.children}
                        task={child}
                        task_deps={@task_deps}
                        nested={true}
                      />
                    </div>
                  </div>
                  <form id="split-work" phx-submit="split_work" class="mt-2 space-y-2">
                    <textarea
                      name="goal"
                      class="textarea textarea-bordered textarea-sm w-full"
                      placeholder="Goal for the lead agent to split across specialists"
                    />
                    <select name="lead_session_id" class="select select-bordered select-sm w-full">
                      <option value="">Lead session (or start one)</option>
                      <option :for={session <- @sessions} value={session.id}>
                        {session.display_name}
                      </option>
                    </select>
                    <select name="provider" class="select select-bordered select-sm w-full">
                      <option value="">Provider for new specialists</option>
                      <option :for={key <- Providers.ui_keys()} value={key}>
                        {Providers.ui_label(key)}
                      </option>
                    </select>
                    <div class="desk-muted flex flex-wrap gap-3 text-xs">
                      <label class="flex items-center gap-1">
                        <input
                          type="checkbox"
                          name="lanes[]"
                          value="backend"
                          checked
                          class="checkbox checkbox-sm"
                        /> Backend
                      </label>
                      <label class="flex items-center gap-1">
                        <input
                          type="checkbox"
                          name="lanes[]"
                          value="frontend"
                          checked
                          class="checkbox checkbox-sm"
                        /> UI / frontend
                      </label>
                      <label class="flex items-center gap-1">
                        <input
                          type="checkbox"
                          name="lanes[]"
                          value="tests"
                          checked
                          class="checkbox checkbox-sm"
                        /> Tests
                      </label>
                    </div>
                    <.button class="btn btn-xs">Split work</.button>
                  </form>
                  <form id="create-task" phx-submit="create_task" class="mt-2 space-y-2">
                    <input
                      name="title"
                      class="input input-bordered input-sm w-full"
                      placeholder="New task"
                    />
                    <details class="desk-details">
                      <summary>Skills, recipient, isolation</summary>
                      <div class="mt-2 space-y-2">
                        <select name="provider" class="select select-bordered select-sm w-full">
                          <option value="">Provider</option>
                          <option :for={key <- Providers.ui_keys()} value={key}>
                            {Providers.ui_label(key)}
                          </option>
                        </select>
                        <select name="role_id" class="select select-bordered select-sm w-full">
                          <option value="">Role</option>
                          <option :for={role <- @roles} value={role.id}>{role.name}</option>
                        </select>
                        <select name="isolated" class="select select-bordered select-sm w-full">
                          <option value="true" selected>Isolated worktree</option>
                          <option value="false">Shared primary tree</option>
                        </select>
                        <select
                          name="permission_profile"
                          class="select select-bordered select-sm w-full"
                        >
                          <option value="default">default permission</option>
                          <option value="observer">observer</option>
                          <option value="restricted">restricted</option>
                        </select>
                        <input
                          name="delegation_depth"
                          class="input input-bordered input-sm w-full"
                          placeholder="Delegation depth"
                        />
                        <input
                          name="skills"
                          class="input input-bordered input-sm w-full"
                          placeholder="Skills (comma separated)"
                        />
                        <select name="recipient_id" class="select select-bordered select-sm w-full">
                          <option value="">Preferred recipient</option>
                          <option :for={session <- @sessions} value={session.id}>
                            {session.display_name}
                          </option>
                        </select>
                        <label class="desk-muted flex items-center gap-2 text-xs">
                          <input
                            type="checkbox"
                            name="auto_recipient"
                            value="true"
                            class="checkbox checkbox-sm"
                          /> Automatic eligible peer
                        </label>
                        <select name="reviewer_id" class="select select-bordered select-sm w-full">
                          <option value="">Reviewer</option>
                          <option :for={session <- @sessions} value={session.id}>
                            {session.display_name}
                          </option>
                        </select>
                        <input
                          name="files"
                          class="input input-bordered input-sm w-full"
                          placeholder="Files to claim (comma separated)"
                        />
                        <input
                          name="checks"
                          class="input input-bordered input-sm w-full"
                          placeholder="Required checks"
                        />
                      </div>
                    </details>
                    <.button class="btn btn-xs">Add task</.button>
                  </form>
                  <form
                    :if={match?([_, _ | _], @tasks)}
                    id="add-task-dependency"
                    phx-submit="add_task_dependency"
                    class="mt-2 space-y-2"
                  >
                    <select name="task_id" class="select select-bordered select-sm w-full">
                      <option :for={task <- @tasks} value={task.id}>{task.title}</option>
                    </select>
                    <select name="depends_on_id" class="select select-bordered select-sm w-full">
                      <option :for={task <- @tasks} value={task.id}>{task.title}</option>
                    </select>
                    <.button class="btn btn-xs">Wait on</.button>
                  </form>
                  <form id="run-workflow" phx-submit="run_workflow" class="mt-2 space-y-2">
                    <input
                      name="name"
                      class="input input-bordered input-sm w-full"
                      placeholder="Workflow name"
                    />
                    <textarea
                      name="steps"
                      class="textarea textarea-bordered textarea-sm w-full"
                      placeholder="Design\nImplement\nReview"
                    />
                    <.button class="btn btn-xs">Save and run workflow</.button>
                  </form>
                  <div :if={@workflows != []} id="workflow-list" class="mt-2 flex flex-wrap gap-1">
                    <button
                      :for={workflow <- @workflows}
                      type="button"
                      phx-click="instantiate_workflow"
                      phx-value-id={workflow.id}
                      class="btn btn-xs btn-ghost"
                    >
                      Run {workflow.name}
                    </button>
                  </div>
                </div>
              </.context_card>

              <.context_card title="Messages">
                <div id="message-panel">
                  <p :if={@messages == [] and @inbox == []} class="desk-empty">No messages yet.</p>
                  <div
                    :for={{group, items} <- grouped_conversations(@messages, @inbox)}
                    id={"conversation-#{conversation_dom_id(group)}"}
                    class="mb-3 space-y-1"
                  >
                    <p class="desk-kicker">{conversation_label(group)}</p>
                    <p
                      :for={item <- items}
                      class="mb-1 flex flex-wrap items-center gap-2 text-xs"
                    >
                      <.status_chip status={item.delivery_state} />
                      <span>{item.kind} · {item.scope} · {item.body}</span>
                      <span :if={item.correlation_id} class="desk-muted">
                        · corr {short_sha(item.correlation_id)}
                      </span>
                      <span :if={item.reply_to_message_id} class="desk-muted">
                        · reply {short_sha(item.reply_to_message_id)}
                      </span>
                      <span :if={message_refs(item) != []} class="desk-muted">
                        · {Enum.join(message_refs(item), ", ")}
                      </span>
                    </p>
                  </div>
                </div>
              </.context_card>

              <.context_card title="Artifacts">
                <div id="artifact-panel">
                  <p :if={@artifacts == []} class="desk-empty">No artifacts yet.</p>
                  <p
                    :for={artifact <- @artifacts}
                    class={artifact.state != "available" && "text-warning"}
                  >
                    {artifact.kind} · {artifact.name} · {artifact.mime_type} · {artifact.size_bytes} B · {short_sha(
                      artifact.sha256
                    )}
                    <span :if={artifact.revision_of_id}>
                      · rev of {short_sha(artifact.revision_of_id)}
                    </span>
                    · {artifact.state}
                  </p>
                </div>
              </.context_card>

              <.context_card title="Merge queue">
                <div id="merge-queue">
                  <p :if={@merge_queue == []} class="desk-empty">No handoffs waiting.</p>
                  <div :for={item <- @merge_queue} id={"merge-item-#{item.id}"} class="mb-3 space-y-1">
                    <p class="flex flex-wrap items-center gap-2">
                      <.status_chip status={item.status} />
                      <span>{item.summary}</span>
                    </p>
                    <p class="desk-muted text-xs">
                      {item.branch_name} → {item.target_ref}
                      <span :if={item.commit_sha}>· {short_sha(item.commit_sha)}</span>
                      · policy {item.policy_status}
                    </p>
                    <p :if={policy_summary(item)} class="desk-muted text-xs">
                      {policy_summary(item)}
                    </p>
                    <p :if={handoff_files(@artifacts, item) != []} class="desk-muted text-xs">
                      files {Enum.join(handoff_files(@artifacts, item), ", ")} · {length(
                        handoff_files(@artifacts, item)
                      )} changed
                    </p>
                    <p :if={handoff_commits(item, @worktrees, @artifacts)} class="desk-muted text-xs">
                      base {short_sha(elem(handoff_commits(item, @worktrees, @artifacts), 0))} → head {short_sha(
                        elem(handoff_commits(item, @worktrees, @artifacts), 1)
                      )}
                    </p>
                    <p :if={handoff_warnings(@artifacts, item) != []} class="text-warning text-xs">
                      warnings {Enum.join(handoff_warnings(@artifacts, item), ", ")}
                    </p>
                    <p :if={handoff_artifact(@artifacts, item)} class="desk-muted text-xs">
                      artifact {short_sha(handoff_artifact(@artifacts, item).id)}
                      <span :if={handoff_artifact(@artifacts, item).context_id}>
                        · context {short_sha(handoff_artifact(@artifacts, item).context_id)}
                      </span>
                      <span :if={handoff_artifact(@artifacts, item).task_id}>
                        · task {short_sha(handoff_artifact(@artifacts, item).task_id)}
                      </span>
                    </p>
                    <p
                      :if={handoff_held_leases(@leases, item) != []}
                      class="text-warning text-xs"
                    >
                      still holding {Enum.join(
                        Enum.map(handoff_held_leases(@leases, item), & &1.resource_key),
                        ", "
                      )}
                    </p>
                    <div
                      :if={handoff_review_messages(@messages, @artifacts, item) != []}
                      id={"handoff-review-#{item.id}"}
                      class="mt-1 space-y-1"
                    >
                      <p class="desk-kicker">Review conversation</p>
                      <p
                        :for={message <- handoff_review_messages(@messages, @artifacts, item)}
                        class="text-xs"
                      >
                        {message.kind} · {message.body}
                      </p>
                    </div>
                    <p :if={item.policy_status == "failed"} class="text-warning text-xs">
                      Checks blocked merge
                    </p>
                    <div class="flex flex-wrap gap-1 pt-1">
                      <button
                        :if={item.status == "queued"}
                        type="button"
                        phx-click="accept_queue_item"
                        phx-value-artifact_id={item.artifact_id}
                        class="btn btn-xs"
                      >
                        Accept
                      </button>
                      <button
                        :if={item.status in ["queued", "accepted"]}
                        type="button"
                        phx-click="reject_queue_item"
                        phx-value-artifact_id={item.artifact_id}
                        class="btn btn-xs"
                      >
                        Reject
                      </button>
                      <button
                        :if={item.status in ["queued", "accepted"]}
                        type="button"
                        phx-click="review_handoff"
                        phx-value-id={item.id}
                        class="btn btn-xs"
                      >
                        Open review
                      </button>
                      <button
                        :if={
                          item.status == "accepted" and not merge_blocked?(item, @worktrees) and
                            @confirm_merge_id != item.id
                        }
                        type="button"
                        id={"confirm-merge-#{item.id}"}
                        phx-click="confirm_merge"
                        phx-value-id={item.id}
                        class="btn btn-xs"
                      >
                        Merge
                      </button>
                      <button
                        :if={@confirm_merge_id == item.id}
                        type="button"
                        id={"merge-#{item.id}"}
                        phx-click="merge_queue_item"
                        phx-value-id={item.id}
                        class="btn btn-xs btn-error"
                      >
                        Confirm merge
                      </button>
                      <button
                        :if={@confirm_merge_id == item.id}
                        type="button"
                        phx-click="cancel_merge"
                        class="btn btn-xs"
                      >
                        Cancel
                      </button>
                    </div>
                  </div>
                </div>
              </.context_card>

              <.context_card title="Worktree">
                <div id="worktree-panel">
                  <p :if={@unexpected_edits != []} id="unexpected-edits" class="text-warning">
                    Unexpected main-tree edits: {length(@unexpected_edits)}
                  </p>
                  <p :if={!@active_worktree} class="desk-empty">No isolated worktree.</p>
                  <div :if={@active_worktree} class="space-y-2">
                    <p>{@active_worktree.branch_name} · {@active_worktree.status}</p>
                    <pre id="worktree-diff" class="desk-scroll max-h-32 text-xs">{@worktree_diff}</pre>
                    <form id="commit-worktree" phx-submit="commit_worktree" class="space-y-2">
                      <input
                        name="message"
                        class="input input-bordered input-sm w-full"
                        placeholder="Commit message"
                      />
                      <.button class="btn btn-xs">Commit</.button>
                    </form>
                    <form id="publish-handoff" phx-submit="publish_handoff" class="space-y-2">
                      <input
                        name="summary"
                        class="input input-bordered input-sm w-full"
                        placeholder="Handoff summary"
                      />
                      <.button class="btn btn-xs">Handoff</.button>
                    </form>
                    <button
                      :if={!@confirm_cleanup}
                      type="button"
                      id="cleanup-worktree"
                      phx-click="cleanup_worktree"
                      class="btn btn-ghost btn-xs"
                    >
                      Cleanup worktree
                    </button>
                    <button
                      :if={@confirm_cleanup}
                      type="button"
                      id="confirm-cleanup-worktree"
                      phx-click="confirm_cleanup"
                      class="btn btn-error btn-xs"
                    >
                      Confirm cleanup
                    </button>
                  </div>
                </div>
              </.context_card>

              <.context_card title="Usage">
                <div id="usage-panel">
                  <p class="tabular-nums">
                    {@usage["input_tokens"]} in / {@usage["output_tokens"]} out / {@usage[
                      "total_tokens"
                    ]} total
                  </p>
                  <p class="desk-muted text-xs tabular-nums">{@usage["cost_cents"]} cents</p>
                </div>
              </.context_card>

              <.context_card title="Search">
                <div id="search-panel" class="space-y-2">
                  <p id="search-status" class="desk-muted">
                    {@search_status.status} · {@search_status.adapter}
                  </p>
                  <form id="project-search" phx-submit="search_project" class="space-y-2">
                    <input
                      name="q"
                      value={@search_query}
                      class="input input-bordered input-sm w-full"
                      placeholder="Search project"
                      aria-label="Search project"
                    />
                    <.button class="btn btn-xs">Search</.button>
                  </form>
                  <button
                    type="button"
                    id="rebuild-search"
                    phx-click="rebuild_search"
                    class="btn btn-ghost btn-xs"
                    aria-label="Rebuild search index"
                  >
                    Rebuild index
                  </button>
                  <p :if={@search_results == []} class="desk-empty">No search results.</p>
                  <div
                    :for={{group, hits} <- grouped_search(@search_results)}
                    class="desk-search-group"
                  >
                    <p class="desk-kicker mb-1">{search_group_label(group)}</p>
                    <div :for={hit <- hits} class="mb-2 text-xs">
                      <p>{hit[:title] || hit["title"] || hit[:text]}</p>
                      <p class="desk-muted">
                        {hit[:source] || hit[:namespace] || group} · {hit[:retrieval] || "lexical"}
                      </p>
                      <p class="desk-muted">{hit_context(hit)}</p>
                      <button
                        :if={hit[:namespace] && hit[:id]}
                        type="button"
                        phx-click="forget_memory"
                        phx-value-namespace={hit[:namespace]}
                        phx-value-id={hit[:id]}
                        class="btn btn-ghost btn-xs"
                      >
                        Forget
                      </button>
                    </div>
                  </div>
                  <div :if={@memories != []} id="memory-panel" class="mt-3 space-y-2">
                    <p class="desk-kicker">Memory</p>
                    <div :for={memory <- @memories} class="text-xs">
                      <p>{memory.text}</p>
                      <p class="desk-muted">
                        {memory.namespace}
                        <span :if={memory.metadata["author"]}>
                          · {memory.metadata["author"]}
                        </span>
                        <span :if={memory.metadata["kind"]}>· {memory.metadata["kind"]}</span>
                        · {Calendar.strftime(memory.inserted_at, "%Y-%m-%d %H:%M")}
                      </p>
                      <button
                        type="button"
                        phx-click="forget_memory"
                        phx-value-namespace={memory.namespace}
                        phx-value-id={memory.id}
                        class="btn btn-ghost btn-xs"
                      >
                        Forget
                      </button>
                    </div>
                  </div>
                </div>
              </.context_card>

              <.context_card title="Team sync">
                <div id="sync-panel" class="space-y-2">
                  <button
                    type="button"
                    id="export-sync"
                    phx-click="export_sync"
                    class="btn btn-ghost btn-xs"
                    aria-label="Export sync bundle"
                  >
                    Export bundle
                  </button>
                  <p :if={@sync_path} id="sync-path" class="desk-muted break-all text-xs">
                    {@sync_path}
                  </p>
                  <form id="import-sync" phx-submit="import_sync" class="space-y-2">
                    <input
                      name="path"
                      class="input input-bordered input-sm w-full"
                      placeholder="Path to bundle.json"
                      aria-label="Sync bundle path"
                    />
                    <.button class="btn btn-xs">Import bundle</.button>
                  </form>
                </div>
              </.context_card>

              <.context_card title="A2A">
                Agent Cards, delegations, durable messages, leases, and artifacts persist in SQLite.
              </.context_card>
            </div>
          </aside>
        </div>
      </main>
    </div>

    <Layouts.flash_group flash={@flash} />
    """
  end

  attr :title, :string, required: true
  slot :inner_block, required: true

  defp context_card(assigns) do
    ~H"""
    <section class="desk-card">
      <h3 class="desk-kicker mb-2">{@title}</h3>
      <div class="desk-card-body">
        {render_slot(@inner_block)}
      </div>
    </section>
    """
  end

  attr :task, :map, required: true
  attr :task_deps, :map, default: %{}
  attr :nested, :boolean, default: false

  defp task_item(assigns) do
    ~H"""
    <div id={"task-#{@task.id}"} class={if(@nested, do: "mb-1", else: "mb-2")}>
      <p class="flex flex-wrap items-center gap-2">
        <span :if={@nested && crew_child_label(@task)} class="desk-muted text-xs">
          {crew_child_label(@task)}
        </span>
        <span>{@task.title}</span>
        <.status_chip status={@task.status} />
        <span
          :if={match?([_ | _], Map.get(@task_deps, @task.id, []))}
          class="desk-muted text-xs"
        >
          waits on {Enum.join(Map.get(@task_deps, @task.id, []), ", ")}
        </span>
      </p>
      <button
        :if={completable_task?(@task)}
        type="button"
        phx-click="complete_task"
        phx-value-id={@task.id}
        class="btn btn-xs mt-1"
      >
        Complete
      </button>
    </div>
    """
  end

  defp crew_child_label(task), do: crew_lane(task) || crew_kind(task)

  attr :status, :string, required: true

  defp status_chip(assigns) do
    ~H"""
    <span class={["desk-status", status_tone(@status)]}>
      <span class="desk-status-dot" aria-hidden="true"></span>
      <span class="tabular-nums">{@status}</span>
    </span>
    """
  end

  defp upload_error_text(:too_large), do: "File is too large (20 MB max)."
  defp upload_error_text(:too_many_files), do: "Too many attachments (8 max)."
  defp upload_error_text(:not_accepted), do: "That file type is not accepted."
  defp upload_error_text(other), do: "Could not attach file (#{inspect(other)})."
end
