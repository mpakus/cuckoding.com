defmodule Boss.TaskPromptTest do
  use Boss.DataCase, async: false

  alias Boss.{Projects, Repo, Tasks}
  alias Boss.Agents.{Claude, Codex, OpenCode}
  alias Boss.Projects.{SpecImporter, TaskPrompt}
  alias Boss.Tasks.Task

  setup do
    root =
      Path.join(
        System.tmp_dir!(),
        "boss-task-prompt-#{Base.url_encode64(:crypto.strong_rand_bytes(12), padding: false)}"
      )

    File.mkdir!(root)
    on_exit(fn -> File.rm_rf!(root) end)

    doc_root = Path.join(root, "doc-repo")
    specs_root = Path.join(root, "specs-repo")
    File.mkdir!(doc_root)
    File.mkdir!(specs_root)
    File.mkdir!(Path.join(doc_root, "docs"))
    specs = Path.join(specs_root, "specs")
    File.mkdir!(specs)

    for repo_dir <- [doc_root, specs_root] do
      {_, 0} = System.cmd("git", ["-C", repo_dir, "init", "-b", "main"])

      {_, 0} =
        System.cmd("git", [
          "-C",
          repo_dir,
          "-c",
          "user.name=Test",
          "-c",
          "user.email=test@example.invalid",
          "commit",
          "--allow-empty",
          "-m",
          "initial"
        ])
    end

    {:ok, doc_project} =
      Projects.create_project(%{
        name: "Doc App",
        root_path: doc_root,
        specs_path: "docs",
        intake_mode: "documentation",
        base_branch: "main"
      })

    {:ok, specs_project} =
      Projects.create_project(%{
        name: "Specs App",
        root_path: specs_root,
        specs_path: "specs",
        intake_mode: "specs",
        base_branch: "main"
      })

    %{root: root, specs: specs, doc_project: doc_project, specs_project: specs_project}
  end

  test "read-only CLI arguments and task_prompt_schema.json stay strictly read-only" do
    schema_path = Application.app_dir(:boss, "priv/task_prompt_schema.json")
    schema = schema_path |> File.read!() |> Jason.decode!()
    assert schema["additionalProperties"] == false
    assert schema["required"] == ["summary", "actions"]

    item_schema = get_in(schema, ["properties", "actions", "items"])
    assert item_schema["additionalProperties"] == false

    assert Enum.sort(item_schema["required"]) ==
             Enum.sort(Map.keys(item_schema["properties"]))

    codex_args =
      Codex.selection_args(:task_prompt, "/tmp/out.json", %{
        model_id: "gpt-6-astra",
        reasoning_effort: "high"
      })

    assert "--sandbox" in codex_args

    assert Enum.at(codex_args, Enum.find_index(codex_args, &(&1 == "--sandbox")) + 1) ==
             "read-only"

    assert schema_path in codex_args
    assert "--model" in codex_args

    claude_args = Claude.stage_args(:task_prompt, %{model_id: "claude-sonnet-4-6"})
    assert "--permission-mode" in claude_args
    assert "dontAsk" in claude_args
    assert "Read,Glob,Grep" in claude_args

    opencode_args =
      OpenCode.args(:task_prompt, %{model_id: "opencode/beam-free", reasoning_effort: "high"})

    assert opencode_args == [
             "run",
             "--pure",
             "--format",
             "json",
             "--model",
             "opencode/beam-free",
             "--variant",
             "high"
           ]

    [{"OPENCODE_PERMISSION", perm_json} | _] = OpenCode.env(:task_prompt)
    perm = Jason.decode!(perm_json)
    assert perm["*"] == "deny"
    assert perm["read"] == "allow"
  end

  test "decode/1 enforces schema, rejects duplicate/unknown keys, and extracts fenced JSON" do
    valid = """
    ```json
    {
      "summary": "Create rate limiter task and block billing.",
      "actions": [
        {
          "op": "create_task",
          "task_ref": "api-rate-limit",
          "title": "Add API rate limiting",
          "specification": "Enforce token-bucket limits on public endpoints.",
          "acceptance": ["Returns 429 with Retry-After header"],
          "depends_on": ["m1-auth"],
          "reason": null
        },
        {
          "op": "block_task",
          "task_ref": "m7-billing",
          "reason": "Waiting on Stripe webhook secret"
        }
      ]
    }
    ```
    """

    assert {:ok, %{"summary" => _, "actions" => [create, block]}} = TaskPrompt.decode(valid)
    assert create["op"] == "create_task"
    assert create["task_ref"] == "api-rate-limit"
    assert block["op"] == "block_task"
    assert block["title"] == nil

    assert {:error, :duplicate_keys} =
             TaskPrompt.decode(~s({"summary":"a","summary":"b","actions":[]}))

    assert {:error, :unknown_fields} =
             TaskPrompt.decode(~s({"summary":"a","actions":[],"extra":1}))

    assert {:error, :invalid_op} =
             TaskPrompt.decode(
               ~s({"summary":"bad","actions":[{"op":"mark_done","task_ref":"1","title":null,"specification":null,"acceptance":null,"depends_on":null,"reason":null}]})
             )

    assert {:error, :invalid_task_id} =
             TaskPrompt.decode(
               ~s({"summary":"bad slug","actions":[{"op":"create_task","task_ref":"../bad","title":"Bad","specification":"Body","acceptance":["ok"],"depends_on":[],"reason":null}]})
             )
  end

  test "creates, updates, and controls tasks on documentation projects", %{doc_project: project} do
    {:ok, %{task: base_task}} =
      Projects.record_spec(project.id, %{
        relative_path: "autopilot/m1-auth.md",
        explicit_id: "m1-auth",
        title: "Authentication foundation",
        original_text: "---\ndepends_on: []\n---\n# Authentication foundation\n\nInitial spec.\n"
      })

    runner = fn "opencode", _path, prompt, _deadline ->
      assert prompt =~ "m1-auth"
      assert prompt =~ "Authentication foundation"

      %{
        "status" => "finished",
        "cleanup" => "group_empty",
        "report" => %{
          "summary" => "Updated m1-auth spec, created rate-limit task, and blocked it.",
          "actions" => [
            %{
              "op" => "update_task_spec",
              "task_ref" => "m1-auth",
              "title" => "Authentication with magic links",
              "specification" => "Implement magic-link login and session rotation.",
              "acceptance" => ["Magic-link token expires after 15 minutes"],
              "depends_on" => [],
              "reason" => nil
            },
            %{
              "op" => "create_task",
              "task_ref" => "api-rate-limit",
              "title" => "API rate limiter",
              "specification" => "Add per-IP rate limiting after auth.",
              "acceptance" => ["429 response on burst above threshold"],
              "depends_on" => [Integer.to_string(base_task.id)],
              "reason" => nil
            },
            %{
              "op" => "block_task",
              "task_ref" => "api-rate-limit",
              "title" => nil,
              "specification" => nil,
              "acceptance" => nil,
              "depends_on" => nil,
              "reason" => "Confirm burst threshold with product owner"
            }
          ]
        }
      }
    end

    assert {:ok, receipt} =
             TaskPrompt.run(
               project.id,
               Ecto.UUID.generate(),
               %{
                 prompt: "Update m1-auth to magic links and add blocked rate limiter task",
                 agent: "opencode",
                 check_command: "mix test",
                 reviewer: "codex"
               },
               runner: runner
             )

    assert Enum.map(receipt.results, & &1.status) == [:applied, :applied, :applied]

    updated_auth = Repo.get!(Task, base_task.id)
    assert updated_auth.title == "Authentication with magic links"
    assert updated_auth.state == "new"
    assert updated_auth.state_version == 1

    [_, created_entry, _] = receipt.results
    created_task = Repo.get!(Task, created_entry.task_id)
    assert created_task.title == "API rate limiter"
    assert created_task.state == "blocked"
    assert created_task.attention_reason == "Confirm burst threshold with product owner"

    {:ok, details} = Tasks.get_details(project.id, created_task.id)
    assert Enum.map(details.dependencies.dependencies, & &1.reference) == ["m1-auth"]
  end

  test "creates and updates Markdown files on specs projects without SpecImporter drift", %{
    specs_project: project,
    specs: specs_dir
  } do
    runner = fn "codex", _path, _prompt, _deadline ->
      %{
        "status" => "finished",
        "cleanup" => "group_empty",
        "report" => %{
          "summary" => "Created healthcheck spec.",
          "actions" => [
            %{
              "op" => "create_task",
              "task_ref" => "healthcheck-endpoint",
              "title" => "Healthcheck endpoint",
              "specification" => "Expose GET /health returning 200 OK.",
              "acceptance" => ["GET /health returns 200 JSON status"],
              "depends_on" => [],
              "reason" => nil
            }
          ]
        }
      }
    end

    assert {:ok, %{results: [%{status: :applied, task_id: task_id}]}} =
             TaskPrompt.run(
               project.id,
               Ecto.UUID.generate(),
               %{
                 prompt: "Create a healthcheck task",
                 agent: "codex",
                 check_command: "",
                 reviewer: "codex"
               },
               runner: runner
             )

    spec_file = Path.join([specs_dir, "prompts", "healthcheck-endpoint.md"])
    assert File.regular?(spec_file)

    assert {:ok, %{created: 0, revised: 0, unchanged: 1, missing: 0}} =
             SpecImporter.sync(project.id)

    assert Repo.get!(Task, task_id).state == "new"
  end

  test "invalid targets and empty queue cancellations leave later actions available", c do
    attrs = %{relative_path: "target.md", title: "Target", original_text: "# Target"}
    {:ok, %{task: task}} = Projects.record_spec(c.doc_project.id, attrs)
    {:ok, %{task: other}} = Projects.record_spec(c.specs_project.id, attrs)

    actions = [
      %{"op" => "cancel_queued_workflow", "task_ref" => to_string(task.id)},
      %{"op" => "add_task_note", "task_ref" => to_string(other.id), "reason" => "Wrong project"},
      %{"op" => "add_task_note", "task_ref" => to_string(task.id), "reason" => "Correct project"}
    ]

    assert {:ok, %{results: [cancel, wrong_project, note]}} =
             TaskPrompt.apply_report(c.doc_project.id, %{"actions" => actions})

    assert %{status: :failed, task_id: id, detail: detail} = cancel
    assert id == task.id
    assert detail =~ "No queued or paused"
    assert %{status: :failed, task_id: nil, detail: detail} = wrong_project
    assert detail =~ "not found in this project"
    assert %{status: :applied, task_id: ^id} = note
  end

  for change <- [:none, :edited, :imported, :adopted, :moved, :symlink_parent] do
    @change change
    test "spec updates compare the source seen by the prompt with #{change} working files", c do
      dir = Path.join(c.specs, "features")
      File.mkdir!(dir)
      path = Path.join(dir, "target.md")
      original = "---\nid: target\n---\n# Target\n"
      edited = original <> "An owner's new requirement.\n"
      File.write!(path, original)
      assert {:ok, _} = SpecImporter.sync(c.specs_project.id)
      [entry] = Projects.list_spec_entries(c.specs_project.id)

      runner = fn _, _, _, _ ->
        case @change do
          :none ->
            :ok

          :edited ->
            File.write!(path, edited)

          :imported ->
            File.write!(path, edited)
            assert {:ok, _} = SpecImporter.sync(c.specs_project.id)

          :adopted ->
            File.write!(path, edited)
            assert {:ok, _} = SpecImporter.sync(c.specs_project.id)

            task = Repo.get!(Task, entry.task_id)
            latest = List.last(Projects.list_spec_revisions(task.spec_id))

            assert {:ok, _} =
                     Tasks.transition(task.id, %{
                       action: "adopt_revision",
                       project_id: c.specs_project.id,
                       spec_revision_id: latest.id,
                       expected_version: task.state_version,
                       command_id: Ecto.UUID.generate()
                     })

          :symlink_parent ->
            retained = Path.join(c.root, "retained")
            File.rename!(dir, retained)
            File.ln_s!(retained, dir)

          :moved ->
            File.rename!(path, Path.join(c.specs, "moved.md"))
            assert {:ok, _} = SpecImporter.sync(c.specs_project.id)
        end

        update = %{
          "op" => "update_task_spec",
          "task_ref" => "target",
          "title" => "Updated",
          "specification" => "New description.",
          "acceptance" => ["Works"],
          "depends_on" => []
        }

        %{
          "status" => "finished",
          "cleanup" => "group_empty",
          "report" => %{"actions" => [update]}
        }
      end

      assert {:ok, %{results: [result]}} =
               TaskPrompt.run(
                 c.specs_project.id,
                 Ecto.UUID.generate(),
                 %{agent: "codex", prompt: "Update target", reviewer: "codex"},
                 runner: runner
               )

      if @change == :none do
        assert result.status == :applied
        assert File.read!(path) =~ "New description."
        assert {:ok, %{revised: 0}} = SpecImporter.sync(c.specs_project.id)
      else
        assert result.status == :failed
        assert result.detail =~ "source changed"

        case @change do
          :moved ->
            refute File.exists?(path)
            assert File.read!(Path.join(c.specs, "moved.md")) == original

          :symlink_parent ->
            assert File.read!(Path.join(c.root, "retained/target.md")) == original

          _ ->
            assert File.read!(path) == edited
        end

        refute Enum.any?(
                 Projects.list_spec_revisions(Repo.get!(Task, entry.task_id).spec_id),
                 &String.contains?(&1.original_text, "New description.")
               )

        assert Repo.get!(Task, entry.task_id).title == "Target"
      end
    end
  end

  test "a late numeric task cannot receive an update from an earlier prompt", %{
    doc_project: project
  } do
    runner = fn _, _, _, _ ->
      assert {:ok, %{task: task}} =
               Projects.record_spec(project.id, %{
                 title: "Later",
                 relative_path: "later.md",
                 original_text: "# Later"
               })

      update = %{
        "op" => "update_task_spec",
        "task_ref" => to_string(task.id),
        "title" => "Wrong",
        "specification" => "Replacement",
        "acceptance" => ["Replacement"],
        "depends_on" => []
      }

      %{"status" => "finished", "cleanup" => "group_empty", "report" => %{"actions" => [update]}}
    end

    assert {:ok, %{results: [%{status: :failed, detail: detail}]}} =
             TaskPrompt.run(
               project.id,
               Ecto.UUID.generate(),
               %{agent: "codex", prompt: "Update tasks"},
               runner: runner
             )

    assert detail =~ "source changed"
    assert [%{title: "Later", task_id: id}] = Projects.list_spec_entries(project.id)

    assert [%{original_text: "# Later"}] =
             Projects.list_spec_revisions(Repo.get!(Task, id).spec_id)
  end

  test "enforces one active prompt per project and supports Stop cancellation", %{
    doc_project: project
  } do
    parent = self()
    req_id = Ecto.UUID.generate()

    slow_runner = fn _agent, _path, _prompt, _deadline ->
      send(parent, :prompt_started)

      receive do
        :stop -> %{"status" => "cancelled", "cleanup" => "group_empty"}
      after
        5_000 -> %{"status" => "failed", "cleanup" => "group_empty"}
      end
    end

    repo = Repo.get_dynamic_repo()
    repo_pid = if is_atom(repo), do: Process.whereis(repo), else: repo

    worker =
      Elixir.Task.async(fn ->
        Repo.put_dynamic_repo(repo_pid)

        TaskPrompt.run(
          project.id,
          req_id,
          %{prompt: "Slow prompt", agent: "codex", check_command: "", reviewer: "codex"},
          runner: slow_runner
        )
      end)

    assert_receive :prompt_started, 2_000
    assert TaskPrompt.active?(project.id)

    assert {:error, :busy} =
             TaskPrompt.run(
               project.id,
               Ecto.UUID.generate(),
               %{
                 prompt: "Concurrent prompt",
                 agent: "codex",
                 check_command: "",
                 reviewer: "codex"
               },
               runner: slow_runner
             )

    assert :ok = TaskPrompt.stop(project.id, req_id)
    assert {:error, :cancelled} = Elixir.Task.await(worker, 2_000)
    refute TaskPrompt.active?(project.id)
  end

  test "queues/cancels workflows and resumes/resets tasks using explicit check command", %{
    doc_project: project
  } do
    # Keep this request queued while the prompt exercises cancellation.
    {:ok, _} =
      Projects.record_spec(project.id, %{
        relative_path: "waiting.md",
        explicit_id: "waiting",
        title: "Waiting",
        original_text: "# Waiting"
      })

    {:ok, %{task: task}} =
      Projects.record_spec(project.id, %{
        relative_path: "prompts/ops-target.md",
        explicit_id: "ops-target",
        title: "Queue and state target",
        original_text:
          "---\nid: \"ops-target\"\ndepends_on: [waiting]\n---\n# Queue and state target\n\nBody.\n"
      })

    # Malformed check_command override is rejected cleanly before queueing
    {:ok, blocked_receipt} =
      TaskPrompt.apply_report(
        project.id,
        %{
          "summary" => "Try queue with malformed check command.",
          "actions" => [
            %{
              "op" => "queue_workflow",
              "task_ref" => "ops-target",
              "title" => nil,
              "specification" => nil,
              "acceptance" => nil,
              "depends_on" => nil,
              "reason" => nil
            }
          ]
        },
        %{check_command: "mix 'unterminated", reviewer: "codex"}
      )

    assert [%{status: :failed, detail: detail}] = blocked_receipt.results
    assert detail =~ "Check command"

    # With explicit check_command, queue_workflow followed by cancel_queued_workflow succeeds
    {:ok, queued_receipt} =
      TaskPrompt.apply_report(
        project.id,
        %{
          "summary" => "Queue then cancel queued workflow, block, resume, cancel, and reset.",
          "actions" => [
            %{
              "op" => "queue_workflow",
              "task_ref" => "ops-target",
              "title" => nil,
              "specification" => nil,
              "acceptance" => nil,
              "depends_on" => nil,
              "reason" => nil
            },
            %{
              "op" => "cancel_queued_workflow",
              "task_ref" => "ops-target",
              "title" => nil,
              "specification" => nil,
              "acceptance" => nil,
              "depends_on" => nil,
              "reason" => nil
            },
            %{
              "op" => "needs_input_task",
              "task_ref" => "ops-target",
              "title" => nil,
              "specification" => nil,
              "acceptance" => nil,
              "depends_on" => nil,
              "reason" => "Clarify timeout value"
            },
            %{
              "op" => "resume_task",
              "task_ref" => "ops-target",
              "title" => nil,
              "specification" => nil,
              "acceptance" => nil,
              "depends_on" => nil,
              "reason" => nil
            },
            %{
              "op" => "cancel_task",
              "task_ref" => "ops-target",
              "title" => nil,
              "specification" => nil,
              "acceptance" => nil,
              "depends_on" => nil,
              "reason" => "Temporarily dropped"
            },
            %{
              "op" => "retry_task",
              "task_ref" => "ops-target",
              "title" => nil,
              "specification" => nil,
              "acceptance" => nil,
              "depends_on" => nil,
              "reason" => nil
            }
          ]
        },
        %{check_command: "mix test", reviewer: "codex"}
      )

    assert Enum.all?(queued_receipt.results, &(&1.status == :applied))
    final_task = Repo.get!(Task, task.id)
    assert final_task.state == "new"
    assert final_task.attention_reason == nil
  end
end
