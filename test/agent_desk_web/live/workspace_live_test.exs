defmodule AgentDeskWeb.WorkspaceLiveTest do
  use AgentDeskWeb.ConnCase

  import Phoenix.LiveViewTest

  alias AgentDesk.A2A
  alias AgentDesk.Agents
  alias AgentDesk.GitRepo
  alias AgentDesk.Projects
  alias AgentDesk.Providers
  alias AgentDesk.Providers.Event
  alias AgentDesk.Providers.SessionWorker
  alias AgentDesk.Repo
  alias AgentDesk.Resources.Manager
  alias AgentDesk.Roles
  alias AgentDesk.Search.Memory
  alias AgentDesk.Security.ControlAuth
  alias AgentDesk.Scope
  alias AgentDesk.Worktrees

  test "renders the workspace shell", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/")

    assert html =~ "Cuckoding"
    assert has_element?(view, "#open-project")
    assert has_element?(view, "#recent-projects")
    assert has_element?(view, "#agent-grove")
    assert has_element?(view, "#first-run")
    assert render(view) =~ "Idle until a session starts"
    assert render(view) =~ "No projects opened yet."
    assert render(view) =~ "Select a Git repository"
    assert has_element?(view, "#onboard-next")
    assert has_element?(view, "#onboard-next[disabled]")
    assert has_element?(view, "#shortcuts-help")
    assert render(view) =~ "step 1 of 10"
    html = render_click(view, "onboard_next", %{})
    assert html =~ "Finish this onboarding step before continuing."
    assert render(view) =~ "step 1 of 10"
    refute has_element?(view, "#theme-toggle")
    refute html =~ "paste a path"
    refute has_element?(view, "#project-path")
    refute has_element?(view, "#open-project-form")
    refute html =~ "phx:set-theme"
  end

  test "choose folder asks the native picker", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/")

    assert html =~ "Choose folder"
    assert has_element?(view, "#choose-repo")

    view
    |> element("#choose-repo")
    |> render_click()

    assert_push_event(view, "tauri_command", %{
      command: "dialog_open",
      payload: %{directory: true, title: "Choose a Git repository", defaultPath: _}
    })
  end

  test "reports a native picker failure", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    html = render_click(view, "picker_failed", %{"error" => "denied"})
    assert html =~ "Could not open the macOS folder picker."
  end

  test "explains why a provider session could not start", %{conn: conn} do
    repo = GitRepo.tmp_repo!()
    {:ok, project} = Projects.open_project(repo)
    {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}")

    html = render_click(view, "start_session", %{"provider" => "nope", "display_name" => "X"})
    assert html =~ "That provider is not supported."
  end

  test "rejects sensitive events for a session owned by another project", %{conn: conn} do
    first_repo = GitRepo.tmp_repo!()
    second_repo = GitRepo.tmp_repo!()
    {:ok, first_project} = Projects.open_project(first_repo)
    {:ok, second_project} = Projects.open_project(second_repo)

    {:ok, foreign_session} =
      Providers.start_session(Scope.for_project(second_project), %{
        provider: "codex",
        display_name: "Foreign"
      })

    {:ok, view, _html} = live(conn, ~p"/projects/#{first_project.id}")

    html = render_click(view, "resume_session", %{"id" => foreign_session.id})
    assert html =~ "That action is not authorized for this project."

    AgentDesk.Projects.Supervisor.stop_runtime(first_project.id)
    AgentDesk.Projects.Supervisor.stop_runtime(second_project.id)
  end

  test "requires server-side confirmation before terminating a session", %{conn: conn} do
    repo = GitRepo.tmp_repo!()
    {:ok, project} = Projects.open_project(repo)

    {:ok, session} =
      Providers.start_session(Scope.for_project(project), %{
        provider: "codex",
        display_name: "Protected"
      })

    {:ok, other_session} =
      Providers.start_session(Scope.for_project(project), %{
        provider: "codex",
        display_name: "Other"
      })

    {:ok, worker} = SessionWorker.fetch(session.id)
    {:ok, other_worker} = SessionWorker.fetch(other_session.id)
    {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}")
    view |> element("#tab-#{session.id}") |> render_click()

    html = render_click(view, "terminate", %{})
    assert html =~ "That action is not authorized for this project."
    assert Process.alive?(worker)

    _ = render_click(view, "confirm_terminate", %{})
    view |> element("#tab-#{other_session.id}") |> render_click()

    html = render_click(view, "terminate", %{})
    assert html =~ "That action is not authorized for this project."
    assert Process.alive?(worker)
    assert Process.alive?(other_worker)

    AgentDesk.Projects.Supervisor.stop_runtime(project.id)
  end

  test "stale control sockets cannot cross mutation boundaries", %{conn: conn} do
    repo = GitRepo.tmp_repo!()
    {:ok, project} = Projects.open_project(repo)
    scope = Scope.for_project(project)
    {:ok, session} = Providers.start_session(scope, %{provider: "fake", display_name: "Guarded"})
    {:ok, worker} = SessionWorker.fetch(session.id)
    worktree = Worktrees.get_for_session(session.id)

    {:ok, memory} =
      %Memory{}
      |> Memory.changeset(%{
        project_id: project.id,
        namespace: "shared",
        text: "must survive a stale socket"
      })
      |> Repo.insert()

    {:ok, [lease]} =
      Manager.claim(
        Scope.for_agent(project, session),
        [%{"type" => "file", "key" => "lib/guarded.ex", "mode" => "exclusive"}],
        reason: "authorization test"
      )

    cases = [
      %{family: "registry install", event: "registry_install", params: %{"id" => "cline"}},
      %{family: "registry remove", event: "registry_remove", params: %{"id" => "cline"}},
      %{
        family: "role save",
        event: "save_role",
        params: %{"name" => "stale-role", "permission_profile" => "default"}
      },
      %{
        family: "memory delete",
        event: "forget_memory",
        params: %{"namespace" => memory.namespace, "id" => memory.id}
      },
      %{
        family: "delegation decision",
        event: "accept_delegation",
        params: %{"id" => AgentDesk.Ids.generate()}
      },
      %{
        family: "crew change",
        event: "split_work",
        params: %{"goal" => "stale crew", "lanes" => ["backend"]}
      },
      %{
        family: "task change",
        event: "create_task",
        params: %{"title" => "stale task"}
      },
      %{
        family: "workflow change",
        event: "run_workflow",
        params: %{"name" => "stale workflow", "steps" => "one\ntwo"}
      },
      %{family: "sync export", event: "export_sync", params: %{}},
      %{family: "sync import", event: "import_sync", params: %{"path" => "/missing"}},
      %{family: "approval", event: "approve", params: %{"id" => "stale-request"}},
      %{
        family: "lease revoke",
        event: "revoke_lease",
        params: %{"id" => lease.id},
        prepare: [{"confirm_revoke_lease", %{"id" => lease.id}}]
      },
      %{
        family: "lease revoke confirmation",
        event: "confirm_revoke_lease",
        params: %{"id" => lease.id}
      },
      %{
        family: "session start",
        event: "start_session",
        params: %{"provider" => "fake", "display_name" => "Stale"}
      },
      %{
        family: "session terminate",
        event: "terminate",
        params: %{},
        prepare: [{"confirm_terminate", %{}}]
      },
      %{
        family: "worktree cleanup",
        event: "confirm_cleanup",
        params: %{},
        prepare: [{"cleanup_worktree", %{}}]
      },
      %{
        family: "project close confirmation",
        event: "confirm_close_project",
        params: %{"id" => project.id}
      },
      %{
        family: "recent forget confirmation",
        event: "confirm_forget_recent",
        params: %{"id" => project.id}
      },
      %{
        family: "handoff merge",
        event: "merge_queue_item",
        params: %{"id" => "stale-merge"},
        prepare: [{"confirm_merge", %{"id" => "stale-merge"}}]
      },
      %{
        family: "handoff merge confirmation",
        event: "confirm_merge",
        params: %{"id" => "stale-merge"}
      },
      %{family: "search rebuild", event: "rebuild_search", params: %{}},
      %{
        family: "transcript shortcut",
        event: "shortcut",
        params: %{"action" => "load_older"}
      },
      %{
        family: "project settings",
        event: "set_delegation_policy",
        params: %{"depth" => "8"}
      }
    ]

    stale_views =
      Enum.map(cases, fn test_case ->
        {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}")

        Enum.each(test_case[:prepare] || [], fn {event, params} ->
          _ = render_click(view, event, params)
        end)

        {test_case, view}
      end)

    role_ids_before = project |> Roles.list() |> MapSet.new(& &1.id)
    tasks_before = length(A2A.list_tasks(scope))
    sessions_before = length(Agents.visible_sessions(scope))
    :ok = ControlAuth.rotate_binding_for_test()

    Enum.each(stale_views, fn {test_case, view} ->
      result = render_click(view, test_case.event, test_case.params)

      assert match?({:error, {:redirect, %{to: "/control/unauthorized"}}}, result),
             "#{test_case.family} did not reject the stale control socket: #{inspect(result)}"
    end)

    assert project |> Roles.list() |> MapSet.new(& &1.id) == role_ids_before
    assert Repo.get(Memory, memory.id)
    assert length(A2A.list_tasks(scope)) == tasks_before
    assert length(Agents.visible_sessions(scope)) == sessions_before
    assert Enum.any?(Manager.list_project(project.id), &(&1.id == lease.id))
    assert Process.alive?(worker)
    assert File.dir?(worktree.path)
    assert {:ok, %{open: true}} = Projects.get_project(project.id)
  end

  test "authorized sockets retain control project and session mutations", %{conn: conn} do
    repo = GitRepo.tmp_repo!()
    {:ok, project} = Projects.open_project(repo)
    scope = Scope.for_project(project)
    {:ok, session} = Providers.start_session(scope, %{provider: "fake", display_name: "Allowed"})
    {:ok, worker} = SessionWorker.fetch(session.id)

    {:ok, memory} =
      %Memory{}
      |> Memory.changeset(%{
        project_id: project.id,
        namespace: "shared",
        text: "authorized deletion"
      })
      |> Repo.insert()

    {:ok, [lease]} =
      Manager.claim(
        Scope.for_agent(project, session),
        [%{"type" => "file", "key" => "lib/allowed.ex", "mode" => "exclusive"}],
        reason: "authorization test"
      )

    cases = [
      %{
        family: "control",
        event: "registry_install",
        params: %{"id" => "cline"},
        verify: fn -> assert Repo.get_by(AgentDesk.Providers.AcpInstall, registry_id: "cline") end
      },
      %{
        family: "project role",
        event: "save_role",
        params: %{"name" => "authorized-role", "permission_profile" => "default"},
        verify: fn -> assert Enum.any?(Roles.list(project), &(&1.name == "authorized-role")) end
      },
      %{
        family: "project memory",
        event: "forget_memory",
        params: %{"namespace" => memory.namespace, "id" => memory.id},
        verify: fn -> refute Repo.get(Memory, memory.id) end
      },
      %{
        family: "project task",
        event: "create_task",
        params: %{"title" => "authorized task"},
        verify: fn ->
          assert Enum.any?(A2A.list_tasks(scope), &(&1.title == "authorized task"))
        end
      },
      %{
        family: "project sync",
        event: "export_sync",
        params: %{},
        verify: fn ->
          assert File.exists?(Path.join(AgentDesk.Storage.sync_dir(project.id), "bundle.json"))
        end
      },
      %{
        family: "project lease",
        event: "revoke_lease",
        params: %{"id" => lease.id},
        prepare: [{"confirm_revoke_lease", %{"id" => lease.id}}],
        verify: fn -> refute Enum.any?(Manager.list_project(project.id), &(&1.id == lease.id)) end
      },
      %{
        family: "session",
        event: "close_tab",
        params: %{"id" => session.id},
        verify: fn ->
          refute Enum.any?(Agents.visible_sessions(scope), &(&1.id == session.id))
          assert Process.alive?(worker)
        end
      }
    ]

    Enum.each(cases, fn test_case ->
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}")

      Enum.each(test_case[:prepare] || [], fn {event, params} ->
        assert is_binary(render_click(view, event, params))
      end)

      result = render_click(view, test_case.event, test_case.params)
      assert is_binary(result), "#{test_case.family} unexpectedly rejected an authorized socket"
      test_case.verify.()
    end)
  end

  test "lists recent projects and opens one from recents", %{conn: conn} do
    repo = GitRepo.tmp_repo!()
    {:ok, project} = Projects.open_project(repo)
    :ok = Projects.close_project(project)

    {:ok, view, html} = live(conn, ~p"/")

    assert html =~ project.name
    assert has_element?(view, "#recent-#{project.id}")
    assert has_element?(view, "#check-recent-#{project.id}")

    view
    |> element("#open-recent-#{project.id}")
    |> render_click()

    html = render(view)
    assert html =~ project.name
    assert html =~ "Opened #{project.name}"
    assert_patch(view, ~p"/projects/#{project.id}")

    AgentDesk.Projects.Supervisor.stop_runtime(project.id)
  end

  test "check again re-validates a recent project", %{conn: conn} do
    repo = GitRepo.tmp_repo!()
    {:ok, project} = Projects.open_project(repo)
    :ok = Projects.close_project(project)

    {:ok, view, _html} = live(conn, ~p"/")

    view
    |> element("#check-recent-#{project.id}")
    |> render_click()

    html = render(view)
    assert html =~ "Checked #{project.name}. Repository is still valid."
    assert_patch(view, ~p"/projects/#{project.id}")

    AgentDesk.Projects.Supervisor.stop_runtime(project.id)
  end

  test "check again shows a missing-folder error and can remove from recents", %{conn: conn} do
    repo = GitRepo.tmp_repo!()
    {:ok, project} = Projects.open_project(repo)
    :ok = Projects.close_project(project)
    File.rm_rf!(repo)

    {:ok, view, html} = live(conn, ~p"/")
    assert html =~ project.name

    view
    |> element("#check-recent-#{project.id}")
    |> render_click()

    html = render(view)
    assert html =~ "That folder is gone. It may have been moved or deleted."
    assert has_element?(view, "#forget-recent-#{project.id}")

    view
    |> element("#forget-recent-#{project.id}")
    |> render_click()

    view
    |> element("#confirm-forget-#{project.id}")
    |> render_click()

    html = render(view)
    refute has_element?(view, "#recent-#{project.id}")
    assert html =~ "Removed #{project.name} from recents."
  end

  test "shows an opened project from a patched URL", %{conn: conn} do
    repo = GitRepo.tmp_repo!()
    {:ok, project} = Projects.open_project(repo)

    {:ok, view, html} = live(conn, ~p"/projects/#{project.id}")

    assert html =~ project.name
    assert has_element?(view, "#recent-projects")

    AgentDesk.Projects.Supervisor.stop_runtime(project.id)
  end

  test "restores the last opened project from the index", %{conn: conn} do
    repo = GitRepo.tmp_repo!()
    {:ok, project} = Projects.open_project(repo)

    {:ok, view, _html} = live(conn, ~p"/")
    assert_patch(view, ~p"/projects/#{project.id}")
    assert render(view) =~ project.name

    AgentDesk.Projects.Supervisor.stop_runtime(project.id)
  end

  test "saves a role and starts a session with it", %{conn: conn} do
    repo = GitRepo.tmp_repo!()
    {:ok, project} = Projects.open_project(repo)
    {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}")
    view |> element("#tab-new") |> render_click()

    assert has_element?(view, "#session-role")
    assert has_element?(view, "#save-role-form")
    assert has_element?(view, "#container-opt-in")

    view
    |> form("#save-role-form",
      name: "auditor",
      description: "Audits handoffs",
      permission_profile: "restricted",
      prompt: "HIDDEN_PROMPT_TOKEN"
    )
    |> render_submit()

    html = render(view)
    assert html =~ "auditor"

    auditor = Enum.find(AgentDesk.Roles.list(project), &(&1.name == "auditor"))

    view
    |> form("#start-session-form",
      provider: "codex",
      display_name: "Audit",
      role_id: auditor.id
    )
    |> render_submit()

    assert render(view) =~ "auditor"
    [session] = Agents.visible_sessions(Scope.for_project(project))
    assert session.role == "auditor"
    assert session.settings["permission_profile"] == "restricted"
  end

  test "creates a session tab and closing it leaves the worker running", %{conn: conn} do
    repo = GitRepo.tmp_repo!()
    {:ok, project} = Projects.open_project(repo)
    {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}")
    view |> element("#tab-new") |> render_click()

    view
    |> form("#start-session-form", provider: "codex", display_name: "Atlas")
    |> render_submit()

    assert render(view) =~ "Atlas"
    [session] = Agents.visible_sessions(Scope.for_project(project))
    assert {:ok, pid} = SessionWorker.fetch(session.id)
    assert has_element?(view, "#isolation-card")
    assert render(view) =~ AgentDesk.Isolation.test_database(session)
    assert File.exists?(Path.join(AgentDesk.Isolation.dir(session), "postgres.schema.sql"))

    view |> element("#close-tab-#{session.id}") |> render_click()
    refute has_element?(view, "#tab-#{session.id}")
    assert Process.alive?(pid)
  end

  test "renders an approval card for a provider permission request", %{conn: conn} do
    repo = GitRepo.tmp_repo!()
    {:ok, project} = Projects.open_project(repo)

    {:ok, session} =
      Providers.start_session(
        Scope.for_project(project),
        %{provider: "fake", display_name: "Approver"},
        peer_args: ["--approval"]
      )

    assert AgentDesk.DataCase.wait_until(fn ->
             AgentDesk.Repo.get!(AgentDesk.Agents.Session, session.id).provider_session_id
           end)

    {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}")
    view |> element("#tab-#{session.id}") |> render_click()
    view |> form("#prompt-composer", prompt: "go") |> render_submit()

    assert AgentDesk.DataCase.wait_until(fn ->
             html = render(view)
             html =~ "approval-card" or html =~ "Allow"
           end)
  end

  test "shows coordination panels for agents, delegations, leases, and artifacts", %{conn: conn} do
    repo = GitRepo.tmp_repo!()
    {:ok, project} = Projects.open_project(repo)
    {:ok, view, html} = live(conn, ~p"/projects/#{project.id}")

    assert has_element?(view, "#agents-directory")
    assert has_element?(view, "#agent-filters")
    assert has_element?(view, "#agent-filter-all")
    assert has_element?(view, "#delegation-inbox")
    assert has_element?(view, "#resource-leases")
    assert has_element?(view, "#artifact-panel")
    assert has_element?(view, "#merge-queue")
    assert has_element?(view, "#task-conversation")
    assert has_element?(view, "#split-work")
    assert has_element?(view, "#create-task")
    assert has_element?(view, "#run-workflow")
    assert has_element?(view, "#message-panel")
    assert has_element?(view, "#worktree-panel")
    assert has_element?(view, "#search-panel")
    assert has_element?(view, "#rebuild-search")
    assert has_element?(view, "#sync-panel")
    assert has_element?(view, "#export-sync")
    assert has_element?(view, "#tab-dashboard")
    assert has_element?(view, "#tab-new")
    assert has_element?(view, "#session-tabs")
    view |> element("#tab-new") |> render_click()
    assert has_element?(view, "#new-session")
    assert has_element?(view, "#shared-opt-in")
    assert has_element?(view, "#sidebar-queues")
    assert has_element?(view, "#sidebar-tasks")
    assert has_element?(view, "#sidebar-agents")
    assert has_element?(view, "#sidebar-delegations")
    assert has_element?(view, "#sidebar-handoffs")
    assert has_element?(view, "#sidebar-search")
    assert html =~ "Isolated worktree"
    assert html =~ "Automatic eligible peer"
    assert html =~ "No active leases"
  end

  test "exports a team sync bundle from the workspace", %{conn: conn} do
    repo = GitRepo.tmp_repo!()
    {:ok, project} = Projects.open_project(repo)
    {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}")

    view |> element("#export-sync") |> render_click()
    assert has_element?(view, "#sync-path")
    assert render(view) =~ "bundle.json"
  end

  test "shows live badges for two open projects and overlap previews", %{conn: conn} do
    repo_a = GitRepo.tmp_repo!()
    repo_b = GitRepo.tmp_repo!()
    {:ok, a} = Projects.open_project(repo_a)
    {:ok, b} = Projects.open_project(repo_b)
    scope = Scope.for_project(a)
    {:ok, alice} = Agents.create_session(scope, %{provider: "fake", display_name: "Alice"})
    {:ok, bob} = Agents.create_session(scope, %{provider: "fake", display_name: "Bob"})

    assert {:ok, _} =
             AgentDesk.Resources.Manager.claim(
               Scope.for_agent(a, alice),
               [%{"type" => "directory", "key" => "lib", "mode" => "shared"}],
               reason: "browse"
             )

    assert {:ok, _} =
             AgentDesk.Resources.Manager.claim(
               Scope.for_agent(a, bob),
               [%{"type" => "file", "key" => "lib/app.ex", "mode" => "shared"}],
               reason: "read"
             )

    {:ok, view, html} = live(conn, ~p"/projects/#{a.id}")
    assert html =~ "live"
    assert has_element?(view, "#close-project-#{b.id}")
    assert render(view) =~ "overlaps"
    assert render(view) =~ "Send message"
    assert render(view) =~ "Wait and retry"
    assert render(view) =~ "Request release"

    view |> element("#close-project-#{b.id}") |> render_click()
    view |> element("#confirm-close-#{b.id}") |> render_click()

    assert AgentDesk.Projects.Runtime.fetch(b.id) == {:error, :not_started}
    assert {:ok, _} = AgentDesk.Projects.Runtime.fetch(a.id)
  end

  test "starts a remote attach session and shows usage totals", %{conn: conn} do
    repo = GitRepo.tmp_repo!()
    {:ok, project} = Projects.open_project(repo)
    {:ok, view, html} = live(conn, ~p"/projects/#{project.id}")

    assert html =~ "ACP Registry"
    assert has_element?(view, "#usage-panel")
    view |> element("#tab-new") |> render_click()
    assert has_element?(view, "#start-session-form")

    view
    |> form("#start-session-form", provider: "remote", display_name: "Offbox")
    |> render_submit()

    assert has_element?(view, "#remote-connect")

    assert AgentDesk.DataCase.wait_until(fn ->
             sessions = Agents.visible_sessions(Scope.for_project(project))
             match?([%{provider: "remote"}], sessions)
           end)
  end

  test "installs an ACP registry agent and starts a session", %{conn: conn} do
    repo = GitRepo.tmp_repo!()
    {:ok, project} = Projects.open_project(repo)
    {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}")

    view |> element("#view-registry") |> render_click()
    assert has_element?(view, "#acp-registry")
    assert render(view) =~ "Codex"

    view |> element("#registry-install-cline") |> render_click()
    assert has_element?(view, "#registry-use-cline")

    view |> element("#registry-use-cline") |> render_click()
    html = render(view)
    assert html =~ "Cline"
    assert has_element?(view, "#session-tabs")
  end

  test "shows sqlite and xerj analytics", %{conn: conn} do
    repo = GitRepo.tmp_repo!()
    {:ok, project} = Projects.open_project(repo)
    {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}")

    view |> element("#tab-dashboard") |> render_click()
    html = render(view)
    assert has_element?(view, "#agent-analytics")
    assert html =~ "SQLite"
    assert html =~ "Runtime memory"
    assert html =~ "XERJ"
  end

  test "agent directory can message, delegate, and request review", %{conn: conn} do
    repo = GitRepo.tmp_repo!()
    {:ok, project} = Projects.open_project(repo)
    scope = Scope.for_project(project)
    {:ok, alice} = Agents.create_session(scope, %{provider: "fake", display_name: "Alice"})
    {:ok, bob} = Agents.create_session(scope, %{provider: "fake", display_name: "Bob"})

    {:ok, _} =
      AgentDesk.A2A.register_card(Scope.for_agent(project, alice), %{
        name: "Alice",
        description: "Reviewer",
        skills: [%{"id" => "review"}]
      })

    {:ok, _} =
      AgentDesk.A2A.register_card(Scope.for_agent(project, bob), %{
        name: "Bob",
        description: "Implementer",
        skills: [%{"id" => "implement"}]
      })

    {:ok, view, html} = live(conn, ~p"/projects/#{project.id}")
    assert html =~ "Delegate task"
    assert html =~ "Request review"
    assert html =~ "fake"
    assert has_element?(view, "#status-live")
    assert has_element?(view, "#agent-filter-review")
    assert has_element?(view, "#agent-filter-implement")
    assert has_element?(view, "#agent-card-#{alice.id}")
    assert has_element?(view, "#agent-card-#{bob.id}")
    assert render(view) =~ "assigned"

    view |> element("#agent-filter-review") |> render_click()
    assert has_element?(view, "#agent-card-#{alice.id}")
    refute has_element?(view, "#agent-card-#{bob.id}")

    view |> element("#agent-filter-all") |> render_click()
    assert has_element?(view, "#agent-card-#{bob.id}")

    view
    |> element(~s(button[phx-click="message_agent"][phx-value-id="#{bob.id}"]))
    |> render_click()

    assert has_element?(view, "#peer-compose")

    view
    |> form("#peer-compose", %{body: "Hello from Alice"})
    |> render_submit()

    assert render(view) =~ "Hello from Alice" or render(view) =~ "Message queued"

    view |> element("#open-agent-#{bob.id}") |> render_click()
    assert has_element?(view, "#tab-#{bob.id}[aria-selected=true]")
  end

  test "saves shortcuts and lists project areas in the sidebar", %{conn: conn} do
    repo = GitRepo.tmp_repo!()
    {:ok, project} = Projects.open_project(repo)
    {:ok, view, html} = live(conn, ~p"/projects/#{project.id}")

    assert has_element?(view, "#sidebar-nav")
    assert has_element?(view, "#shortcuts-help")
    assert html =~ "Tasks"
    assert html =~ "Handoffs"

    view
    |> form("#shortcut-form", send: "Control+Enter")
    |> render_submit()

    assert render(view) =~ "Control+Enter"
  end

  test "rejects a delegation with a reason", %{conn: conn} do
    repo = GitRepo.tmp_repo!()
    {:ok, project} = Projects.open_project(repo)
    scope = Scope.for_project(project)
    {:ok, alice} = Agents.create_session(scope, %{provider: "fake", display_name: "Alice"})
    {:ok, bob} = Agents.create_session(scope, %{provider: "fake", display_name: "Bob"})
    alice_scope = Scope.for_agent(project, alice)

    {:ok, context} = AgentDesk.A2A.create_context(alice_scope, %{title: "Auth"})

    {:ok, task} =
      AgentDesk.A2A.create_task(alice_scope, context, %{
        title: "Add magic link",
        metadata: %{"skills" => ["elixir"]}
      })

    {:ok, _delegation} =
      AgentDesk.A2A.propose_delegation(alice_scope, %{
        task_id: task.id,
        to_agent_id: bob.id,
        reason: "Please implement",
        idempotency_key: "ui-reject-1"
      })

    {:ok, view, html} = live(conn, ~p"/projects/#{project.id}")
    assert html =~ "Reject with reason"
    assert html =~ "elixir"

    view |> element("#tab-#{bob.id}") |> render_click()

    view
    |> form(~s(#delegation-inbox form[phx-submit="reject_delegation"]), reason: "too busy")
    |> render_submit()

    html = render(view)
    assert html =~ "too busy"
    assert html =~ "rejected"
  end

  test "creates a task with isolation and provider metadata", %{conn: conn} do
    repo = GitRepo.tmp_repo!()
    {:ok, project} = Projects.open_project(repo)
    {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}")

    view
    |> form("#create-task",
      title: "Ship auth",
      provider: "codex",
      isolated: "true",
      permission_profile: "restricted",
      skills: "elixir,liveview",
      auto_recipient: "true"
    )
    |> render_submit()

    html = render(view)
    assert html =~ "Ship auth"
    [task] = AgentDesk.A2A.list_tasks(Scope.for_project(project))
    assert task.metadata["provider"] == "codex"
    assert task.metadata["isolated"] == true
    assert task.metadata["permission_profile"] == "restricted"
    assert "elixir" in task.metadata["skills"]
  end

  test "splits work across existing specialist sessions", %{conn: conn} do
    repo = GitRepo.tmp_repo!()
    {:ok, project} = Projects.open_project(repo)
    scope = Scope.for_project(project)

    {:ok, lead} =
      Agents.create_session(scope, %{provider: "fake", display_name: "Lead", role: "lead"})

    {:ok, _backend} =
      Agents.create_session(scope, %{provider: "fake", display_name: "Backend", role: "backend"})

    {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}")

    view
    |> form("#split-work",
      goal: "Ship billing",
      lead_session_id: lead.id,
      lanes: ["backend"]
    )
    |> render_submit()

    html = render(view)
    assert html =~ "Ship billing"
    assert html =~ "Backend"
    assert html =~ "0/1 lanes done"
    assert html =~ "review waiting"

    parent =
      Enum.find(
        AgentDesk.A2A.list_tasks(scope),
        &(&1.metadata["orchestration"]["kind"] == "parent")
      )

    assert has_element?(view, "#task-group-#{parent.id}")
  end

  test "starts a session from the new-session control", %{conn: conn} do
    repo = GitRepo.tmp_repo!()
    {:ok, project} = Projects.open_project(repo)
    {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}")

    assert has_element?(view, "#tab-new")

    view |> element("#tab-new") |> render_click()
    assert has_element?(view, "#new-session")

    view
    |> form("#start-session-form", provider: "codex", display_name: "Nova")
    |> render_submit()

    html = render(view)
    assert html =~ "Nova"
    assert has_element?(view, "#session-tabs")
    assert html =~ "desk-tab-active"
  end

  test "puts each agent in its own tab", %{conn: conn} do
    repo = GitRepo.tmp_repo!()
    {:ok, project} = Projects.open_project(repo)
    scope = Scope.for_project(project)
    {:ok, alice} = Agents.create_session(scope, %{provider: "fake", display_name: "Alice"})
    {:ok, bob} = Agents.create_session(scope, %{provider: "fake", display_name: "Bob"})
    {:ok, view, html} = live(conn, ~p"/projects/#{project.id}")

    assert html =~ "Dashboard"
    assert has_element?(view, "#tab-dashboard")
    assert has_element?(view, "#tab-#{alice.id}")
    assert has_element?(view, "#tab-#{bob.id}")
    assert html =~ "desk-tab-dot"
    assert has_element?(view, "#close-tab-#{alice.id}")
    assert has_element?(view, "#session-tab-scroll")

    view |> element("#tab-#{bob.id}") |> render_click()
    assert has_element?(view, "#tab-#{bob.id}[aria-selected=true]")

    view |> element("#sidebar-agent-#{alice.id}") |> render_click()
    assert has_element?(view, "#tab-#{alice.id}[aria-selected=true]")

    view |> element("#tab-dashboard") |> render_click()
    assert has_element?(view, "#tab-dashboard[aria-selected=true]")
    assert has_element?(view, "#agent-analytics")
  end

  test "disambiguates duplicate agent tab names", %{conn: conn} do
    repo = GitRepo.tmp_repo!()
    {:ok, project} = Projects.open_project(repo)
    scope = Scope.for_project(project)
    {:ok, first} = Agents.create_session(scope, %{provider: "fake", display_name: "Nova"})
    {:ok, second} = Agents.create_session(scope, %{provider: "fake", display_name: "Nova"})
    {:ok, view, html} = live(conn, ~p"/projects/#{project.id}")

    assert has_element?(view, "#tab-#{first.id}")
    assert has_element?(view, "#tab-#{second.id}")
    assert html =~ String.slice(first.id, 0, 4)
    assert html =~ String.slice(second.id, 0, 4)
  end

  test "groups streamed agent tokens into one activity card", %{conn: conn} do
    repo = GitRepo.tmp_repo!()
    {:ok, project} = Projects.open_project(repo)
    scope = Scope.for_project(project)
    {:ok, session} = Agents.create_session(scope, %{provider: "fake", display_name: "mtv2"})

    {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}")
    view |> element("#tab-#{session.id}") |> render_click()

    send(
      view.pid,
      {:session_activity, session.id, [Event.new(:message_delta, %{"text" => "from"}, "codex")],
       "working", nil}
    )

    send(
      view.pid,
      {:session_activity, session.id,
       [
         Event.new(:message_delta, %{"text" => "the"}, "codex"),
         Event.new(:message_delta, %{"text" => "picker"}, "codex")
       ], "working", nil}
    )

    html = render(view)
    assert html =~ "from the picker"
    assert html |> :binary.matches("desk-activity-message_delta") |> length() == 1
  end

  test "search panel does not label off as an error", %{conn: conn} do
    repo = GitRepo.tmp_repo!()
    {:ok, project} = Projects.open_project(repo)
    put_search_config(adapter: :disabled)

    _ = AgentDesk.Search.rebuild(project)
    {:ok, view, html} = live(conn, ~p"/projects/#{project.id}")

    refute html =~ "error: Disabled"
    refute html =~ "error · Disabled"
    assert render(view) =~ "Off. Enable search"
  end

  test "omits untitled tool cards and shows a titled tool with a failure reason", %{conn: conn} do
    repo = GitRepo.tmp_repo!()
    {:ok, project} = Projects.open_project(repo)
    scope = Scope.for_project(project)
    {:ok, session} = Agents.create_session(scope, %{provider: "fake", display_name: "tools"})

    {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}")
    view |> element("#tab-#{session.id}") |> render_click()

    send(
      view.pid,
      {:session_activity, session.id,
       [Event.new(:tool_completed, %{"status" => "completed"}, "cursor")], "working", nil}
    )

    refute render(view) =~ "tool completed"

    send(
      view.pid,
      {:session_activity, session.id,
       [
         Event.new(
           :tool_completed,
           %{
             "title" => "Read README",
             "status" => "failed",
             "reason" => "path is outside the worktree"
           },
           "cursor"
         )
       ], "working", nil}
    )

    html = render(view)
    assert html =~ "Read README"
    assert html =~ "path is outside the worktree"
    refute html =~ "%{"
  end

  test "prompt composer accepts file attachments", %{conn: conn} do
    repo = GitRepo.tmp_repo!()
    {:ok, project} = Projects.open_project(repo)
    scope = Scope.for_project(project)
    {:ok, session} = Agents.create_session(scope, %{provider: "fake", display_name: "files"})

    {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}")
    view |> element("#tab-#{session.id}") |> render_click()

    assert has_element?(view, "#prompt-composer")
    assert render(view) =~ "Attach"
    assert render(view) =~ "Paste or drop"
  end

  test "opens a dedicated handoff review screen", %{conn: conn} do
    repo = GitRepo.tmp_repo!()
    {:ok, project} = Projects.open_project(repo)
    {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}")

    view |> render_click("review_handoff", %{})
    assert has_element?(view, "#handoff-review")
    assert render(view) =~ "Handoff review"
  end

  defp put_search_config(config) do
    previous = Application.fetch_env(:agent_desk, :search)
    Application.put_env(:agent_desk, :search, config)
    on_exit(fn -> restore_search_config(previous) end)
  end

  defp restore_search_config({:ok, config}),
    do: Application.put_env(:agent_desk, :search, config)

  defp restore_search_config(:error), do: Application.delete_env(:agent_desk, :search)
end
