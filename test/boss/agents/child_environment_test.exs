defmodule Boss.Agents.ChildEnvironmentTest do
  use ExUnit.Case, async: false
  alias Boss.Agents.Process, as: Runner
  @moduletag skip: :os.type() != {:unix, :darwin}
  @host_keys ~w(MIX_ENV PORT PHX_SERVER BOSS_DATA_DIR)

  setup do
    root = Path.join(System.tmp_dir!(), "boss-child-env-fixture-#{Ecto.UUID.generate()}")
    File.mkdir!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    previous = Map.new(@host_keys, &{&1, System.get_env(&1)})

    System.put_env(%{
      "MIX_ENV" => "dev",
      "PORT" => "4001",
      "PHX_SERVER" => "true",
      "BOSS_DATA_DIR" => Path.join(root, "boss-data")
    })

    on_exit(fn ->
      for {key, value} <- previous do
        if value, do: System.put_env(key, value), else: System.delete_env(key)
      end
    end)

    %{root: root}
  end

  test "native child defaults exclude BOSS launch controls while preserving PATH and tool discovery",
       c do
    python = System.find_executable("python3")

    args = [
      "-c",
      "import json,os; print(json.dumps({k:os.environ.get(k) for k in ['MIX_ENV','PORT','PHX_SERVER','BOSS_DATA_DIR','PATH']}))"
    ]

    {receipt, output} = capture(python, args, cd: c.root)
    assert receipt.outcome == :exited and receipt.exit_code == 0
    assert receipt.cleanup == :group_empty and receipt.eof == %{stdout: true, stderr: true}
    env = JSON.decode!(output["stdout"])
    assert Map.take(env, @host_keys) == Map.new(@host_keys, &{&1, nil})
    assert env["PATH"] == System.fetch_env!("PATH")
    assert System.get_env("MIX_ENV") == "dev"
    assert System.get_env("PHX_SERVER") == "true"
  end

  test "saved mix test selects its project environment without BOSS dev or server settings", c do
    File.mkdir!(Path.join(c.root, "test"))
    File.mkdir!(Path.join(c.root, "config"))

    File.write!(Path.join(c.root, "mix.exs"), """
    defmodule ChildFixture.MixProject do
      use Mix.Project
      def project, do: [app: :child_fixture, version: "0.1.0"]
      def application, do: []
    end
    """)

    File.write!(Path.join(c.root, "config/runtime.exs"), """
    import Config
    config :child_fixture, :launch, %{port: System.get_env("PORT"), server: System.get_env("PHX_SERVER")}
    """)

    File.write!(Path.join(c.root, "test/test_helper.exs"), "ExUnit.start()\n")

    File.write!(Path.join(c.root, "test/environment_test.exs"), """
    defmodule ChildFixture.EnvironmentTest do
      use ExUnit.Case
      test "project defaults" do
        assert to_string(Mix.env()) == System.get_env("CHILD_FIXTURE_ENV", "test")
        assert Application.fetch_env!(:child_fixture, :launch) == %{
          port: System.get_env("CHILD_FIXTURE_PORT"), server: System.get_env("CHILD_FIXTURE_SERVER")}
      end
    end
    """)

    File.cp!(Path.expand("../../../.tool-versions", __DIR__), Path.join(c.root, ".tool-versions"))
    mix = System.find_executable("mix")
    {receipt, output} = capture(mix, ["test"], cd: c.root)
    assert receipt.outcome == :exited and receipt.cleanup == :group_empty
    assert receipt.exit_code == 0, inspect(output)
    assert File.dir?(Path.join(c.root, "_build/test"))
    refute File.exists?(Path.join(c.root, "_build/dev"))

    {receipt, output} =
      capture(mix, ["test"],
        cd: c.root,
        env: [
          {"MIX_ENV", "dev"},
          {"PORT", "4321"},
          {"PHX_SERVER", "false"},
          {"CHILD_FIXTURE_ENV", "dev"},
          {"CHILD_FIXTURE_PORT", "4321"},
          {"CHILD_FIXTURE_SERVER", "false"}
        ]
      )

    assert receipt.exit_code == 0 and receipt.cleanup == :group_empty, inspect(output)
    assert File.dir?(Path.join(c.root, "_build/dev"))
  end

  test "explicit child overrides and env argv keep their selected values and PATH", c do
    selected = Path.join(c.root, "selected-tool")
    File.write!(selected, "#!/bin/sh\nprintf 'PROJECT_TOOLCHAIN'\n")
    File.chmod!(selected, 0o700)
    path = c.root <> ":" <> System.fetch_env!("PATH")
    python = System.find_executable("python3")

    code =
      "import json,os,subprocess; print(json.dumps({'values':{k:os.environ.get(k) for k in ['MIX_ENV','PORT','PHX_SERVER','BOSS_DATA_DIR']},'tool':subprocess.check_output(['selected-tool'],text=True),'path':os.environ['PATH']}))"

    values = %{
      "MIX_ENV" => "project",
      "PORT" => "4321",
      "PHX_SERVER" => "false",
      "BOSS_DATA_DIR" => Path.join(c.root, "project-data")
    }

    for {executable, args, env} <- [
          {python, ["-c", code], Map.to_list(Map.put(values, "PATH", path))},
          {"/usr/bin/env",
           Enum.map(values, fn {key, value} -> "#{key}=#{value}" end) ++ [python, "-c", code],
           [{"PATH", path}]}
        ] do
      {receipt, output} = capture(executable, args, cd: c.root, env: env)
      assert receipt.exit_code == 0 and receipt.cleanup == :group_empty

      assert JSON.decode!(output["stdout"]) == %{
               "values" => values,
               "tool" => "PROJECT_TOOLCHAIN",
               "path" => path
             }
    end

    assert System.get_env("MIX_ENV") == "dev"
    assert System.get_env("PORT") == "4001"
  end

  defp capture(executable, args, opts) do
    table = :ets.new(:child_environment_output, [:set, :public])
    :ets.insert(table, [{:stdout, []}, {:stderr, []}])

    try do
      callback = fn
        {stream, bytes} when stream in [:stdout, :stderr] ->
          [{^stream, previous}] = :ets.lookup(table, stream)
          :ets.insert(table, {stream, [bytes | previous]})
          :ok

        _ ->
          :ok
      end

      result =
        Runner.run(
          executable,
          args,
          opts ++ [input: "", timeout_ms: 15_000, output_limit: 65_536, on_event: callback]
        )

      output =
        Map.new([:stdout, :stderr], fn stream ->
          [{^stream, chunks}] = :ets.lookup(table, stream)
          {to_string(stream), chunks |> Enum.reverse() |> IO.iodata_to_binary()}
        end)

      {result, output}
    after
      :ets.delete(table)
    end
  end
end
