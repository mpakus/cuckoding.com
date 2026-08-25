defmodule AgentDesk.EnvTest do
  use ExUnit.Case, async: false

  alias AgentDesk.Env

  test "merge_path keeps the first occurrence and drops blanks" do
    assert Env.merge_path(["/opt/homebrew/bin:/usr/bin", "/usr/bin:/bin", nil, ""]) ==
             "/opt/homebrew/bin:/usr/bin:/bin"
  end

  test "extra_dirs only includes directories that exist" do
    dirs = Env.extra_dirs()

    assert Enum.all?(dirs, &File.dir?/1)
    assert dirs == Enum.uniq(dirs)
  end

  test "provider environment inherits only local CLI essentials" do
    source = %{
      "PATH" => "/opt/homebrew/bin:/usr/bin",
      "HOME" => "/Users/tester",
      "TMPDIR" => "/private/tmp",
      "LANG" => "en_US.UTF-8",
      "SSH_AUTH_SOCK" => "/private/tmp/ssh.sock",
      "HTTPS_PROXY" => "http://127.0.0.1:8080",
      "OPENAI_API_KEY" => "must-not-leak",
      "AWS_SECRET_ACCESS_KEY" => "must-not-leak",
      "UNRELATED" => "must-not-leak"
    }

    assert Env.provider_environment(source) == %{
             "PATH" => "/opt/homebrew/bin:/usr/bin",
             "HOME" => "/Users/tester",
             "TMPDIR" => "/private/tmp",
             "LANG" => "en_US.UTF-8",
             "SSH_AUTH_SOCK" => "/private/tmp/ssh.sock",
             "HTTPS_PROXY" => "http://127.0.0.1:8080"
           }
  end

  test "provider port environment unsets inherited secrets and merges explicit values" do
    source = %{
      "PATH" => "/usr/bin",
      "OPENAI_API_KEY" => "inherited-secret",
      "AGENTDESK_STALE" => "old"
    }

    port_env =
      %{
        "AGENTDESK_CAPABILITY_TOKEN" => "session-token",
        "AGENTDESK_TEST_PARTITION" => "3",
        "PROVIDER_EXPLICIT_KEY" => "provider-secret"
      }
      |> Env.provider_port_environment(source)
      |> Map.new(fn {key, value} ->
        {List.to_string(key), if(value == false, do: false, else: List.to_string(value))}
      end)

    assert port_env["PATH"] == "/usr/bin"
    assert port_env["OPENAI_API_KEY"] == false
    assert port_env["AGENTDESK_STALE"] == false
    assert port_env["AGENTDESK_CAPABILITY_TOKEN"] == "session-token"
    assert port_env["AGENTDESK_TEST_PARTITION"] == "3"
    assert port_env["PROVIDER_EXPLICIT_KEY"] == "provider-secret"
  end

  test "provider port environment inherits only an explicit validated pass-through list" do
    source = %{
      "PATH" => "/usr/bin",
      "ANTHROPIC_API_KEY" => "explicitly-allowed",
      "OPENAI_API_KEY" => "still-forbidden",
      "UNRELATED" => "still-forbidden"
    }

    assert {:ok, port_env} =
             Env.provider_port_environment(
               %{"ANTHROPIC_API_KEY" => "explicit-value-wins"},
               ["ANTHROPIC_API_KEY"],
               source
             )

    port_env =
      Map.new(port_env, fn {key, value} ->
        {List.to_string(key), if(value == false, do: false, else: List.to_string(value))}
      end)

    assert port_env["PATH"] == "/usr/bin"
    assert port_env["ANTHROPIC_API_KEY"] == "explicit-value-wins"
    assert port_env["OPENAI_API_KEY"] == false
    assert port_env["UNRELATED"] == false
  end

  test "environment pass-through names are bounded and validated" do
    assert {:ok, ["VENDOR_TOKEN"]} =
             Env.validate_env_passthrough(["VENDOR_TOKEN", "VENDOR_TOKEN"])

    assert {:error, :invalid_env_passthrough} =
             Env.validate_env_passthrough(["VALID_NAME", "INVALID=name"])

    assert {:error, :invalid_env_passthrough} =
             Env.validate_env_passthrough(Enum.map(1..65, &"ENV_#{&1}"))
  end

  test "first-party provider policies expose only provider-specific names" do
    assert "OPENAI_API_KEY" in Env.provider_env_passthrough("codex")
    refute "ANTHROPIC_API_KEY" in Env.provider_env_passthrough("codex")

    assert "ANTHROPIC_API_KEY" in Env.provider_env_passthrough("claude")
    refute "OPENAI_API_KEY" in Env.provider_env_passthrough("claude")

    assert Env.provider_env_passthrough("unknown") == []
  end

  test "spawned process receives explicit values but not inherited secrets" do
    inherited_key = "AGENTDESK_INHERITED_SECRET_TEST"
    explicit_key = "AGENTDESK_EXPLICIT_ENV_TEST"
    previous = System.get_env(inherited_key)
    System.put_env(inherited_key, "must-not-reach-child")
    on_exit(fn -> restore_env(inherited_key, previous) end)

    if executable = System.find_executable("printenv") do
      env = Env.provider_port_environment(%{explicit_key => "visible"})

      assert run_printenv(executable, explicit_key, env) == {"visible\n", 0}
      assert run_printenv(executable, inherited_key, env) == {"", 1}
    end
  end

  defp run_printenv(executable, key, env) do
    port =
      Port.open({:spawn_executable, executable}, [
        :binary,
        :exit_status,
        :use_stdio,
        {:args, [key]},
        {:env, env}
      ])

    collect_port_output(port, "")
  end

  defp collect_port_output(port, output) do
    receive do
      {^port, {:data, data}} -> collect_port_output(port, output <> data)
      {^port, {:exit_status, status}} -> {output, status}
    after
      1_000 ->
        Port.close(port)
        flunk("timed out waiting for printenv")
    end
  end

  defp restore_env(key, nil), do: System.delete_env(key)
  defp restore_env(key, value), do: System.put_env(key, value)
end
