defmodule Cuckoding.SharedAgentProfileTest do
  use Cuckoding.DataCase, async: false

  alias Cuckoding.Adapters
  alias Cuckoding.Adapters.{Codex, CursorAgent, SharedProfile, Types}
  alias Cuckoding.AgentRuntime

  setup do
    root = Path.join(System.tmp_dir!(), "shared-agent-test-#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    %{root: root}
  end

  test "one Codex identity probes once for multiple roles and uses the same profile across projects",
       %{root: root} do
    executable = Path.join(root, "codex")
    probe_log = Path.join(root, "probes")
    revoked = Path.join(root, "revoked")

    File.write!(executable, """
    #!/bin/sh
    if [ "$1" = "--version" ]; then echo 'codex-cli 0.146.0'; exit; fi
    printf '%s\\n' "$CODEX_HOME" >> '#{probe_log}'
    if [ -f '#{revoked}' ]; then exit 1; fi
    echo 'Logged in using ChatGPT'
    """)

    File.chmod!(executable, 0o700)
    {:ok, account} = account("codex", executable)
    {:ok, setup} = AgentRuntime.account_setup(account)
    assert setup.command =~ setup.home
    assert {:ok, %{status: "authenticated"}} = AgentRuntime.check_account(account)

    roles = Enum.map(~w(spec_writer reviewer implementer), &%{role_key: &1})
    first = skeleton(root, account, executable, "first")
    second = skeleton(root, account, executable, "second")
    assert {:ok, resolved} = AgentRuntime.resolve_roles(first, roles)
    assert length(String.split(File.read!(probe_log), "\n", trim: true)) == 2
    assert {:ok, next} = AgentRuntime.resolve(second, "implementer")
    assert next.options[:codex_home] == setup.home
    assert resolved["reviewer"].settings["instructions"] == "reviewer instructions"
    assert resolved["spec_writer"].settings["instructions"] == "spec_writer instructions"

    specs =
      for {skeleton, runtime} <- [{first, resolved["implementer"]}, {second, next}] do
        request = request(skeleton)
        assert {:ok, _grant} = Codex.render_config(request, runtime.options)
        assert {:ok, spec} = Codex.launch_spec(request, runtime.options)
        assert spec.environment["CODEX_HOME"] == setup.home
        assert "--ignore-user-config" in spec.command.args
        assert "--ignore-rules" in spec.command.args
        assert ~s(cli_auth_credentials_store="keyring") in spec.command.args
        assert Enum.any?(spec.command.args, &String.starts_with?(&1, "developer_instructions="))
        spec
      end

    refute hd(specs).command.args == List.last(specs).command.args
    refute File.exists?(Path.join(setup.home, "config.toml"))

    setups =
      Enum.map(roles, fn role ->
        {:ok, value} = AgentRuntime.setup(first, role.role_key)
        value
      end)

    assert [%{role_keys: ["implementer", "reviewer", "spec_writer"]}] =
             AgentRuntime.group_setups(setups)

    {:ok, other} = account("codex", executable, "new")
    {:ok, separate} = AgentRuntime.account_setup(other)
    refute separate.home == setup.home

    assert length(
             AgentRuntime.group_setups([
               hd(setups),
               %{hd(setups) | account_id: other.id, authorization_id: other.id}
             ])
           ) ==
             2

    {:ok, second_agent} = account("codex", executable)
    assert second_agent.authorization_account_id == account.id
    assert second_agent.status == "authenticated"
    {:ok, reused} = AgentRuntime.account_setup(second_agent)
    assert reused.command == setup.command

    linked_run = skeleton(root, second_agent, executable, "linked-agent")
    [spec_role, review_role, coding_role] = linked_run.run.workflow_snapshot_json["roles"]
    spec_role = put_in(spec_role["model_ref"], "gpt-6-astra")
    coding_role = put_in(coding_role["model_ref"], "custom-coding-model")
    review_role = put_in(review_role["settings"]["provider_account_id"], account.id)

    linked_run =
      put_in(linked_run.run.workflow_snapshot_json["roles"], [spec_role, review_role, coding_role])

    probes_before = length(String.split(File.read!(probe_log), "\n", trim: true))
    assert {:ok, linked} = AgentRuntime.resolve_roles(linked_run, roles)
    assert length(String.split(File.read!(probe_log), "\n", trim: true)) == probes_before + 1
    assert linked["spec_writer"].requested_model == "gpt-6-astra"
    assert linked["implementer"].requested_model == "custom-coding-model"
    assert linked["implementer"].options[:shared_profile_id] == account.id

    model_request = %{
      request(linked_run)
      | requested_model: linked["implementer"].requested_model
    }

    assert {:ok, _} = Codex.render_config(model_request, linked["implementer"].options)
    assert {:ok, model_spec} = Codex.launch_spec(model_request, linked["implementer"].options)

    assert ["--model", "custom-coding-model"] in Enum.chunk_every(
             model_spec.command.args,
             2,
             1,
             :discard
           )

    File.write!(revoked, "revoked")
    assert {:error, :provider_auth_required} = AgentRuntime.resolve(first, "implementer")
    assert {:ok, %{status: "authentication_required"}} = AgentRuntime.check_account(account)
    assert Adapters.get_provider_account(second_agent.id).status == "authentication_required"
    assert {:error, :provider_auth_required} = AgentRuntime.resolve(linked_run, "implementer")
  end

  test "Cursor shares only its app-owned home while parallel runs retain their permissions", %{
    root: root
  } do
    {:ok, account} = account("cursor_agent", "/usr/bin/true")
    {:ok, setup} = AgentRuntime.account_setup(account)
    home = Path.join(setup.home, "home")
    assert setup.command =~ "HOME='#{home}'"

    specs =
      for name <- ["planning", "coding"] do
        request = request(skeleton(root, account, "/usr/bin/true", name))

        request =
          if name == "planning", do: put_in(request.grant["approval_mode"], "plan"), else: request

        opts = [
          path: "/usr/bin/true",
          shared_profile_id: account.id,
          run_scoped_authenticated?: true
        ]

        assert {:ok, grant} = CursorAgent.render_config(request, opts)
        assert grant.enforced["runtime_home"] == "shared_agent_profile"
        assert {:ok, spec} = CursorAgent.launch_spec(request, opts)
        assert spec.environment["HOME"] == home
        assert String.starts_with?(spec.environment["CURSOR_CONFIG_DIR"], request.run_dir)
        spec
      end

    [plan, coding] = specs
    refute plan.environment["CURSOR_CONFIG_DIR"] == coding.environment["CURSOR_CONFIG_DIR"]
    plan_config = File.read!(Path.join(plan.environment["CURSOR_CONFIG_DIR"], "cli-config.json"))
    refute plan_config =~ "Write(**/*)"

    assert File.read!(Path.join(coding.environment["CURSOR_CONFIG_DIR"], "cli-config.json")) =~
             "Write(**/*)"

    File.write!(Path.join(home, ".cursor/mcp.json"), ~s({"mcpServers":{"evil":{}}}))
    assert {:error, :shared_profile_configuration_changed} = AgentRuntime.account_setup(account)
  end

  test "rejects profile symlinks and runtime identity changes", %{root: root} do
    {:ok, account} = account("codex", "/usr/bin/true")
    {:ok, home} = SharedProfile.prepare(account.id, "codex")
    File.rmdir!(home)
    File.ln_s!(root, home)
    assert {:error, :profile_path_unsafe} = AgentRuntime.account_setup(account)

    assert {:error, :provider_account_mismatch} =
             Adapters.save_provider_account(%{id: account.id, adapter_key: "cursor_agent"})

    refute File.exists?(Path.join(root, "config.toml"))
    assert Adapters.get_provider_account("not-a-uuid") == nil

    assert {:error, :provider_configuration_changed} =
             Adapters.record_provider_status(account.id, "authenticated", %{"settings" => %{}})

    assert Adapters.get_provider_account(account.id).status == "unknown"
  end

  test "authorization references are compatible, immutable and model edits keep sign-in" do
    {:ok, root} = account("codex", "/usr/bin/true")
    {:ok, root} = Adapters.record_provider_status(root.id, "authenticated")
    {:ok, linked} = account("codex", "/usr/bin/true")
    assert {:ok, %{id: root_id}} = Adapters.authorization_account(linked)
    assert root_id == root.id

    assert {:ok, updated} =
             Cuckoding.ProjectOnboarding.save_agent(%{
               "provider_account_id" => root.id,
               "label" => root.label,
               "adapter_key" => "codex",
               "executable_path" => "/usr/bin/true",
               "model" => "gpt-6-astra"
             })

    assert updated.status == "authenticated"
    assert updated.probed_at == root.probed_at

    assert {:error, :provider_account_mismatch} =
             Adapters.save_provider_account(%{
               adapter_key: "cursor_agent",
               label: "Mismatch",
               auth_mode: "shared_profile",
               authorization_account_id: root.id,
               capabilities_json: %{"settings" => %{"executable_path" => "/usr/bin/true"}}
             })

    assert {:error, :provider_account_mismatch} =
             Adapters.save_provider_account(%{
               adapter_key: "codex",
               label: "Missing",
               auth_mode: "shared_profile",
               authorization_account_id: Ecto.UUID.generate(),
               capabilities_json: root.capabilities_json
             })

    assert {:error, :authorization_identity_immutable} =
             Adapters.save_provider_account(%{
               id: linked.id,
               authorization_account_id: "new"
             })

    assert {:error, :invalid_model} =
             Cuckoding.ProjectOnboarding.save_agent(%{
               "label" => "Bad model",
               "adapter_key" => "codex",
               "executable_path" => "/usr/bin/true",
               "model" => "--unsafe\nflag"
             })

    assert {:ok, _} =
             Adapters.save_provider_account(%{
               id: root.id,
               capabilities_json: %{"settings" => %{"executable_path" => "/usr/bin/false"}}
             })

    assert {:error, :provider_account_mismatch} = AgentRuntime.account_setup(linked)
    assert Adapters.get_provider_account(linked.id).status == "unknown"
  end

  defp account(runtime, executable, authorization \\ "auto") do
    Adapters.save_provider_account(%{
      authorization_account_id: authorization,
      adapter_key: runtime,
      label: Ecto.UUID.generate(),
      auth_mode: "shared_profile",
      capabilities_json: %{"settings" => %{"executable_path" => executable}}
    })
  end

  defp skeleton(root, account, executable, name) do
    run_dir = Path.join(root, name)
    File.mkdir_p!(Path.join(run_dir, "agent"))
    File.mkdir_p!(Path.join(run_dir, "worktree"))

    roles =
      Enum.map(~w(spec_writer reviewer implementer), fn role ->
        %{
          "role_key" => role,
          "role_kind" => "agent",
          "adapter_key" => account.adapter_key,
          "settings" => %{
            "provider_account_id" => account.id,
            "executable_path" => executable,
            "instructions" => "#{role} instructions"
          }
        }
      end)

    %{
      run: %{id: Ecto.UUID.generate(), workflow_snapshot_json: %{"roles" => roles}},
      environment: %{run_dir: run_dir}
    }
  end

  defp request(skeleton) do
    %Types.StageRequest{
      project_id: Ecto.UUID.generate(),
      board_id: Ecto.UUID.generate(),
      task_id: Ecto.UUID.generate(),
      stage_key: "implementation",
      attempt_id: Ecto.UUID.generate(),
      requested_model: nil,
      correlation_id: Ecto.UUID.generate(),
      idempotency_key: Ecto.UUID.generate(),
      run_id: skeleton.run.id,
      run_dir: skeleton.environment.run_dir,
      worktree_path: Path.join(skeleton.environment.run_dir, "worktree"),
      objective: "Inspect project",
      grant: %{
        "approval_mode" => "default",
        "tools" => ["read", "write"],
        "resource_limits" => %{"wall_ms" => 60_000}
      },
      plugins: [],
      knowledge: []
    }
  end
end
