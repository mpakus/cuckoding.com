defmodule BossWeb.TaskPromptLiveTest do
  use BossWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  alias Boss.{Projects, Repo}
  alias Boss.Tasks.Task

  setup %{conn: conn} do
    root =
      Path.join(
        System.tmp_dir!(),
        "boss-prompt-ui-#{Base.url_encode64(:crypto.strong_rand_bytes(12), padding: false)}"
      )

    File.mkdir!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    on_exit(fn -> Application.delete_env(:boss, :task_prompt_runner) end)

    docs = Path.join(root, "docs")
    File.mkdir!(docs)
    File.write!(Path.join(root, "mix.exs"), "# fixture\n")

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
        name: "Prompted Project",
        root_path: root,
        specs_path: "docs",
        intake_mode: "documentation",
        base_branch: "main"
      })

    conn = %{conn | host: "127.0.0.1", port: 4002}
    %{conn: conn, project: project}
  end

  test "creates a task and controls existing task via prompt on /projects/:id", %{
    conn: conn,
    project: project
  } do
    {:ok, %{task: existing}} =
      Projects.record_spec(project.id, %{
        relative_path: "autopilot/m1-billing.md",
        explicit_id: "m1-billing",
        title: "Stripe billing integration",
        original_text:
          "---\nid: \"m1-billing\"\ndepends_on: []\n---\n# Stripe billing integration\n\nBody.\n"
      })

    Application.put_env(:boss, :task_prompt_runner, fn agent, _path, prompt, _deadline ->
      assert agent in ~w(codex claude cursor opencode)
      assert prompt =~ "Create webhook verification task and cancel m1-billing"

      %{
        "status" => "finished",
        "cleanup" => "group_empty",
        "report" => %{
          "summary" => "Created webhook-verify task and cancelled m1-billing.",
          "actions" => [
            %{
              "op" => "create_task",
              "task_ref" => "webhook-verify",
              "title" => "Verify webhook HMAC signatures",
              "specification" => "Validate X-Signature header with constant-time comparison.",
              "acceptance" => ["Invalid signatures return 401 Unauthorized"],
              "depends_on" => [],
              "reason" => nil
            },
            %{
              "op" => "cancel_task",
              "task_ref" => "m1-billing",
              "title" => nil,
              "specification" => nil,
              "acceptance" => nil,
              "depends_on" => nil,
              "reason" => "Deferred billing to v2"
            }
          ]
        }
      }
    end)

    {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}")
    assert has_element?(view, "#task-prompt")
    assert has_element?(view, "#open-task-prompt", "Prompt task control")
    refute has_element?(view, "#task-prompt-dialog")

    view |> element("#open-task-prompt") |> render_click()
    assert has_element?(view, "#task-prompt-dialog")
    assert has_element?(view, "#task-prompt-agent")
    assert has_element?(view, "#task-prompt-model")
    refute has_element?(view, "#task-prompt-reviewer")
    refute has_element?(view, "#task-prompt-check")

    view
    |> form("#task-prompt-form", %{
      "prompt" => "Create webhook verification task and cancel m1-billing"
    })
    |> render_change()

    view
    |> form("#task-prompt-form", %{
      "prompt" => "Create webhook verification task and cancel m1-billing"
    })
    |> render_submit()

    render_async(view, 2_000)
    html = render_async(view, 2_000)

    assert html =~ "Created webhook-verify task and cancelled m1-billing."
    assert has_element?(view, "#column-backlog", "Verify webhook HMAC signatures")
    assert has_element?(view, "#column-needs-attention", "Stripe billing integration")
    assert Repo.get!(Task, existing.id).state == "cancelled"

    # Clicking the created task link in the receipt closes the modal and opens the task drawer
    view
    |> element("#task-prompt-results a", "Verify webhook HMAC signatures")
    |> render_click()

    render_async(view, 2_000)
    refute has_element?(view, "#task-prompt-dialog")
    assert has_element?(view, "#task-drawer", "Validate X-Signature header")
  end

  test "keeps draft prompt on failure and supports Stop while running", %{
    conn: conn,
    project: project
  } do
    test_pid = self()

    Application.put_env(:boss, :task_prompt_runner, fn _agent, _path, _prompt, _deadline ->
      send(test_pid, :ui_prompt_running)

      receive do
        :stop -> %{"status" => "cancelled", "cleanup" => "group_empty"}
      after
        5_000 -> %{"status" => "failed", "cleanup" => "group_empty"}
      end
    end)

    {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}")
    view |> element("#open-task-prompt") |> render_click()

    view
    |> form("#task-prompt-form", %{"prompt" => "Create audit log task"})
    |> render_change()

    view
    |> form("#task-prompt-form", %{"prompt" => "Create audit log task"})
    |> render_submit()

    assert_receive :ui_prompt_running, 2_000
    assert has_element?(view, "#task-prompt-stop")

    # Closing the modal while running surfaces toolbar status & Stop without losing state
    view |> element("#close-task-prompt") |> render_click()
    refute has_element?(view, "#task-prompt-dialog")
    assert has_element?(view, "#task-prompt-running")
    assert has_element?(view, "#task-prompt-toolbar-stop")

    view |> element("#open-task-prompt") |> render_click()
    assert has_element?(view, "#task-prompt-dialog")
    view |> element("#task-prompt-stop") |> render_click()
    html = render_async(view, 2_000)

    assert html =~ "Prompt execution stopped."
    assert has_element?(view, "#task-prompt-input", "Create audit log task")
  end
end
