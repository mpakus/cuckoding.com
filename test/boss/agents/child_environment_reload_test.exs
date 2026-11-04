defmodule Boss.Agents.ChildEnvironmentReloadTest do
  use ExUnit.Case, async: false
  @moduletag skip: :os.type() != {:unix, :darwin}

  test "one module reload preserves an existing native owner while new children use isolated env" do
    root = Path.join(System.tmp_dir!(), "boss-environment-reload-#{Ecto.UUID.generate()}")
    File.mkdir!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    source = Path.expand("../../../lib/boss/agents/process.ex", __DIR__)
    current = File.read!(source)

    # Reconstruct the immediately preceding implementation; only this environment
    # block changed in 91d55fb. The rest of the native owner stays byte-identical.
    old =
      current
      |> String.replace(
        ~r/  # These settings configure BOSS.*?  @host_environment ~w\(MIX_ENV PORT PHX_SERVER BOSS_DATA_DIR\)\n/s,
        ""
      )
      |> String.replace(
        ~r/environment =\n      @host_environment.*?      \|> Enum.map\(fn \{key, value\} ->/s,
        "environment =\n      Enum.map(Keyword.get(opts, :env, []), fn {key, value} ->"
      )

    refute old == current
    refute old =~ "@host_environment"
    old_file = Path.join(root, "previous_process.ex")
    File.write!(old_file, old)
    script = Path.join(root, "reload.exs")

    File.write!(script, ~S"""
    [previous, current, root] = System.argv()
    spawn(fn -> Process.sleep(12_000); System.halt(99) end)
    :ok = Application.load(:boss)
    Code.compiler_options(ignore_module_conflict: true)
    [{Boss.Agents.Process, replacement}] = Code.compile_file(current)
    [{Boss.Agents.Process, _}] = Code.compile_file(previous)
    # Compiler introspection may load a module from the code path. Before any
    # native owner exists, discard that unused version and establish a cold slot.
    true = :code.soft_purge(Boss.Agents.Process)
    false = :erlang.check_old_code(Boss.Agents.Process)
    parent = self()
    System.put_env(%{"MIX_ENV" => "dev", "PORT" => "4001", "PHX_SERVER" => "true", "BOSS_DATA_DIR" => "fixture-only"})
    command = "test \"$MIX_ENV\" = dev && test \"$PORT\" = 4001 && test \"$PHX_SERVER\" = true && test \"$BOSS_DATA_DIR\" = fixture-only && printf READY && exec /bin/sleep 8"
    old = spawn(fn ->
      receipt = Boss.Agents.Process.run("/bin/sh", ["-c", command], cd: root,
        timeout_ms: 10_000, output_limit: 1024, on_event: fn
          {:stdout, "READY"} -> send(parent, :old_ready); :ok
          _ -> :ok
        end)
      send(parent, {:old_result, receipt})
    end)
    receive do :old_ready -> :ok after 3000 -> raise "old native child did not start" end
    old_md5 = Boss.Agents.Process.module_info(:md5)
    # Phoenix/Mix's first reload purges only the unused old slot, then moves
    # current code to old. Do not purge or reload again while it is in use.
    false = :code.purge(Boss.Agents.Process)
    true = :code.delete(Boss.Agents.Process)
    {:module, Boss.Agents.Process} = :code.load_binary(Boss.Agents.Process,
      String.to_charlist(current), replacement)
    true = old_md5 != Boss.Agents.Process.module_info(:md5)
    true = :erlang.check_process_code(old, Boss.Agents.Process)
    probe = "test -z \"${MIX_ENV+x}${PORT+x}${PHX_SERVER+x}${BOSS_DATA_DIR+x}\""
    result = Boss.Agents.Process.run("/bin/sh", ["-c", probe], cd: root,
      timeout_ms: 3000, output_limit: 1024)
    %{outcome: :exited, exit_code: 0, cleanup: :group_empty,
      eof: %{stdout: true, stderr: true}} = result
    true = Process.alive?(old)
    send(old, :stop)
    receive do
      {:old_result, %{outcome: :cancelled, cleanup: :group_empty,
        eof: %{stdout: true, stderr: true}, exit_kind: :signal, signal: 15}} -> :ok
    after 4000 -> raise "old owner did not preserve Stop cleanup" end
    "dev" = System.get_env("MIX_ENV")
    IO.puts("OLD_OWNER_CLEAN_NEW_ENV_ISOLATED")
    """)

    assert {"OLD_OWNER_CLEAN_NEW_ENV_ISOLATED\n", 0} =
             System.cmd(
               System.find_executable("elixir"),
               ["-pa", Application.app_dir(:boss, "ebin"), script, old_file, source, root],
               stderr_to_stdout: true
             )
  end
end
