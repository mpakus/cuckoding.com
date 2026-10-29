defmodule BossWeb.WorkflowScopeLiveTest do
  use BossWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  alias Boss.{Deliveries, LocalAccess, Projects, Repo}

  test "a peer claim updates the open drawer when released", %{
    conn: conn
  } do
    project = project("scopes")
    first = planned(project, "one", "lib", "directory")
    second = planned(project, "two", "lib/boss.ex", "file")

    {:ok, implementation} =
      Deliveries.begin_step(first.delivery.id, "implement", 1, %{"plan_step_id" => first.plan.id})

    assert {:error, :scope_conflict} =
             Deliveries.begin_step(second.delivery.id, "implement", 1, %{
               "plan_step_id" => second.plan.id
             })

    {:ok, session} = LocalAccess.exchange(LocalAccess.new_token())
    conn = %{conn | host: "127.0.0.1", port: 4002} |> init_test_session(local_session: session)
    path = "/projects/#{project.id}/tasks/#{second.delivery.task_id}"
    {:ok, view, _} = live(conn, path)
    settle(view)

    assert has_element?(
             view,
             "#scope-wait-#{second.delivery.id}",
             "Waiting for an overlapping workflow"
           )

    assert has_element?(view, "#delivery-#{second.delivery.id}", "Waiting for file scope")
    assert has_element?(view, "#delivery-#{second.delivery.id}", "lib/boss.ex")
    assert has_element?(view, "#stop-delivery-#{second.delivery.id}")

    {:ok, _} =
      Deliveries.finish_step(implementation.id, %{
        "status" => "cancelled",
        "cleanup" => "not_started"
      })

    {:ok, _} = Deliveries.complete(first.delivery.id, "cancelled")
    settle(view)
    refute has_element?(view, "#scope-wait-#{second.delivery.id}")
    assert has_element?(view, "#task-source", "# two")
    assert has_element?(view, "#task-drawer-title", "two")
    assert has_element?(view, "#stop-delivery-#{second.delivery.id}")

    {:ok, reopened, _} = live(conn, path)
    settle(reopened)
    refute has_element?(reopened, "#scope-wait-#{second.delivery.id}")
    assert has_element?(reopened, "#delivery-#{second.delivery.id}", "lib/boss.ex")
  end

  defp project(name) do
    Repo.insert!(%Projects.Project{
      name: name,
      root_path: "/scope-ui/#{name}",
      git_common_dir: "/scope-ui/.git",
      specs_path: "/scope-ui/#{name}/specs",
      base_branch: "main"
    })
  end

  defp planned(project, name, path, kind) do
    {:ok, saved} =
      Projects.record_spec(project.id, %{
        relative_path: name <> ".md",
        title: name,
        original_text: "# " <> name
      })

    {:ok, {:new, delivery}} =
      Deliveries.admit(project.id, saved.task.id, Ecto.UUID.generate(), "true")

    intent = %{
      "run_id" => delivery.id,
      "project_id" => to_string(project.id),
      "repo_path" => project.root_path,
      "git_common_dir" => project.git_common_dir,
      "base_branch" => "main",
      "base_commit" => String.duplicate("a", 40),
      "path" => "/retained/#{delivery.id}"
    }

    {:ok, _} = Deliveries.set_intent(delivery.id, intent)
    {:ok, plan} = Deliveries.begin_step(delivery.id, "plan", 0, %{"workspace" => intent})

    {:ok, _} =
      Deliveries.finish_step(plan.id, %{
        "status" => "finished",
        "cleanup" => "group_empty",
        "exit_kind" => "exit",
        "exit_code" => 0,
        "eof" => %{"stdout" => true, "stderr" => true},
        "report" => %{
          "summary" => "Saved plan",
          "steps" => ["Implement and verify"],
          "acceptance" => ["Preserve source"],
          "file_scopes" => [%{"path" => path, "kind" => kind}]
        }
      })

    %{delivery: delivery, plan: plan}
  end

  defp settle(view) do
    for _ <- 1..3, do: render_async(view, 2_000)
    render(view)
  end
end
