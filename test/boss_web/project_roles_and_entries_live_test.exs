defmodule BossWeb.ProjectRolesAndEntriesLiveTest do
  use BossWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  alias Boss.Agents.{Detections, Roles}
  alias Boss.Checks.Command
  alias Boss.Projects
  alias Boss.Projects.RoleBindings
  alias Boss.Tasks.Entries

  setup %{conn: conn} do
    root =
      Path.join(
        System.tmp_dir!(),
        "boss-proj-roles-#{Base.url_encode64(:crypto.strong_rand_bytes(12), padding: false)}"
      )

    File.mkdir!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    on_exit(fn -> Application.delete_env(:boss, :task_prompt_runner) end)

    docs = Path.join(root, "docs")
    File.mkdir!(docs)

    {_, 0} = System.cmd("git", ["-C", root, "init", "-b", "main"])

    {_, 0} =
      System.cmd("git", [
        "-C",
        root,
        "-c",
        "user.name=Test",
        "-c",
        "user.email=test@example.invalid",
        "commit",
        "--allow-empty",
        "-m",
        "base"
      ])

    {:ok, project} =
      Projects.create_project(%{
        name: "Role Matrix Project",
        root_path: root,
        specs_path: "docs",
        intake_mode: "documentation",
        base_branch: "main"
      })

    {:ok, %{task: task}} =
      Projects.record_spec(project.id, %{
        relative_path: "prompts/spec-verify.md",
        explicit_id: "spec-verify",
        title: "Verify copy against specification",
        original_text:
          "---\nid: \"spec-verify\"\ndepends_on: []\n---\n# Verify copy against specification\n\nEnsure hero headline matches approved product copy.\n"
      })

    # Seed authorized agents & models + multiple role bindings
    for {id, name, models} <- [
          {:cursor, "Cursor Agent",
           [
             %{
               "id" => "gemini-4-carbon",
               "name" => "Gemini 4 Carbon",
               "billing" => "subscription_or_api",
               "pricing" => %{"input" => 1.25, "output" => 10.0, "unit" => "1M tokens"}
             }
           ]},
          {:codex, "Codex",
           [
             %{
               "id" => "gpt-6.2-astra",
               "name" => "GPT-6.2 Astra",
               "billing" => "subscription_or_api",
               "pricing" => %{"input" => 2.5, "output" => 15.0, "unit" => "1M tokens"}
             }
           ]},
          {:claude, "Claude Code",
           [
             %{
               "id" => "claude-opus-4-6",
               "name" => "Claude Opus 4.6",
               "billing" => "subscription_or_api",
               "pricing" => %{"input" => 5.0, "output" => 25.0, "unit" => "1M tokens"}
             }
           ]}
        ] do
      Detections.save_agent(%{
        id: id,
        name: name,
        path: "/tools/#{id}",
        version: "1.2.3",
        probe_status: :ok,
        auth_status: :configured,
        capabilities: %{},
        errors: [],
        models: models
      })
    end

    {:ok, r_cursor} =
      Roles.add_binding("reviewer", "cursor", %{"model_id" => "gemini-4-carbon"})

    {:ok, r_codex} =
      Roles.add_binding("reviewer", "codex", %{"model_id" => "gpt-6.2-astra"})

    {:ok, impl_codex} =
      Roles.add_binding("implementer", "codex", %{"model_id" => "gpt-6.2-astra"})

    {:ok, analytic_claude} =
      Roles.add_binding("analytic", "claude", %{"model_id" => "claude-opus-4-6"})

    conn = %{conn | host: "127.0.0.1", port: 4002}

    %{
      conn: conn,
      project: project,
      task: task,
      bindings: %{
        r_cursor: r_cursor,
        r_codex: r_codex,
        impl_codex: impl_codex,
        analytic_claude: analytic_claude
      }
    }
  end

  test "selects 3 active Agent-Model-Role bindings per project and uses spec-only check by default",
       %{conn: conn, project: project, bindings: b} do
    assert {:ok, %{"mode" => "spec_only", "argv" => []}, _hash} = Command.parse_workflow("")
    assert Command.spec_only?(%{"mode" => "spec_only"})

    {:ok, view, _} = live(conn, ~p"/projects/#{project.id}")
    assert has_element?(view, "#project-roles")
    assert has_element?(view, "#open-project-roles", "Roles & models")
    refute has_element?(view, "#project-roles-dialog")
    refute has_element?(view, "#task-prompt-dialog")

    view |> element("#open-project-roles") |> render_click()
    assert has_element?(view, "#project-roles-dialog")
    assert has_element?(view, "#project-role-reviewer", "Reviews:CursorGemini4Carbon")
    assert has_element?(view, "#project-role-reviewer", "Reviews:CodexGPT6.2Astra")
    assert has_element?(view, "#project-role-implementer", "Implementer:CodexGPT6.2Astra")
    assert has_element?(view, "#project-role-analytic", "Analytic:ClaudeOpus4.6")

    # Select Codex Reviewer, Codex Implementer, Claude Analytic for this project
    view
    |> form("#project-role-form-reviewer", %{
      "role_kind" => "reviewer",
      "choice" => "member:#{b.r_codex.id}"
    })
    |> render_change()

    view
    |> form("#project-role-form-implementer", %{
      "role_kind" => "implementer",
      "choice" => "member:#{b.impl_codex.id}"
    })
    |> render_change()

    view
    |> form("#project-role-form-analytic", %{
      "role_kind" => "analytic",
      "choice" => "member:#{b.analytic_claude.id}"
    })
    |> render_change()

    view |> element("#close-project-roles") |> render_click()
    refute has_element?(view, "#project-roles-dialog")

    saved = RoleBindings.for_project(project.id)
    assert saved["reviewer"].active.agent_id == "codex"
    assert saved["reviewer"].active.model_id == "gpt-6.2-astra"
    assert saved["implementer"].active.agent_id == "codex"
    assert saved["analytic"].active.agent_id == "claude"
    assert saved["analytic"].active.model_id == "claude-opus-4-6"

    # Prompt task control opens in a popup modal and updates agent -> model choices dynamically
    view |> element("#open-task-prompt") |> render_click()
    assert has_element?(view, "#task-prompt-dialog")
    refute has_element?(view, "#task-prompt-reviewer")

    view
    |> form("#task-prompt-form", %{"agent" => "cursor", "prompt" => "Leave note on spec-verify"})
    |> render_change()

    assert has_element?(view, "#task-prompt-model option[value='gemini-4-carbon']")
  end

  test "records collaborative task notes, owner comments, and current state + history in drawer",
       %{conn: conn, project: project, task: task} do
    # Analytic leaves a note via Prompt task control
    Application.put_env(:boss, :task_prompt_runner, fn "claude", _path, _prompt, _deadline ->
      %{
        "status" => "finished",
        "cleanup" => "group_empty",
        "report" => %{
          "summary" => "Added acceptance note on spec-verify.",
          "actions" => [
            %{
              "op" => "add_task_note",
              "task_ref" => "spec-verify",
              "title" => nil,
              "specification" => nil,
              "acceptance" => nil,
              "depends_on" => nil,
              "reason" => "Reviewer should verify typography token --text-ink on mobile."
            }
          ]
        }
      }
    end)

    {:ok, view, _} = live(conn, ~p"/projects/#{project.id}")
    view |> element("#open-task-prompt") |> render_click()

    view
    |> form("#task-prompt-form", %{
      "agent" => "claude",
      "model_id" => "claude-opus-4-6",
      "prompt" => "Add Reviewer note to spec-verify"
    })
    |> render_change()

    view
    |> form("#task-prompt-form", %{
      "agent" => "claude",
      "model_id" => "claude-opus-4-6",
      "prompt" => "Add Reviewer note to spec-verify"
    })
    |> render_submit()

    render_async(view, 2_000)
    render_async(view, 2_000)

    # Also record a Reviewer stage comment
    {:ok, _} =
      Entries.add_comment(project.id, task.id, %{
        author_role: "reviewer",
        agent_id: "cursor",
        model_id: "gemini-4-carbon",
        kind: "comment",
        stage: "review",
        cycle: 1,
        summary: "Approved against specification",
        body: "All specification criteria verified directly against source."
      })

    # Open task drawer and post an Owner comment
    {:ok, drawer_view, _} = live(conn, ~p"/projects/#{project.id}/tasks/#{task.id}")
    render_async(drawer_view, 2_000)

    assert has_element?(drawer_view, "#task-current-state")
    assert has_element?(drawer_view, "#task-activity-log", "Reviews:CursorGemini4Carbon")
    assert has_element?(drawer_view, "#task-activity-log", "Analytic:ClaudeOpus4.6")

    drawer_view
    |> form("#task-comment-form", %{"body" => "Confirmed copy with product lead."})
    |> render_submit()

    render_async(drawer_view, 2_000)

    assert has_element?(drawer_view, "#task-activity-log", "Confirmed copy with product lead.")
    assert has_element?(drawer_view, "#task-activity-log", "Owner")
  end
end
