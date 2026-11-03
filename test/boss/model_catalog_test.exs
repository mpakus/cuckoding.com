defmodule Boss.ModelCatalogTest do
  use ExUnit.Case, async: true
  alias Boss.Agents.ModelCatalog
  alias Boss.Deliveries.ModelPolicy

  test "catalog chooses visible supported roles without inventing aliases or capabilities" do
    {:ok, snapshot} = ModelCatalog.decode(catalog())
    assert snapshot["primary"] == profile("gpt-5.6-sol", "high")
    assert snapshot["resolver"] == profile("gpt-5.6-terra", "xhigh")
    assert snapshot["small"] == profile("gpt-5.6-luna", "medium")

    assert snapshot["fallbacks"] == [
             profile("gpt-5.6-sol", "xhigh"),
             profile("gpt-5.6-terra", "xhigh")
           ]

    assert ModelCatalog.validate(snapshot) == :ok
    refute inspect(snapshot) =~ "SECRET_SENTINEL"

    data = %{"models" => [entry("gpt-6.1-sol", ["medium"]), entry("gpt-6-astra", ["high"])]}
    assert {:ok, constrained} = ModelCatalog.decode(JSON.encode!(data))
    assert constrained["primary"] == profile("gpt-6.1-sol", "medium")
    assert constrained["resolver"] == profile("gpt-6-astra", "high")
    assert constrained["small"] == nil

    data = %{
      "models" => [
        entry("gpt-6-astra"),
        entry("gpt-6.1-sol"),
        entry("gpt-5.6-sol"),
        entry("gpt-5.6-terra")
      ]
    }

    assert {:ok, preferred} = ModelCatalog.decode(JSON.encode!(data))
    assert preferred["primary"]["model"] == "gpt-6.1-sol"
    assert preferred["resolver"]["model"] == "gpt-6-astra"
    assert length(preferred["fallbacks"]) == 4
  end

  test "unlisted, unknown and unsupported models cannot supply the required second model" do
    for second <- [
          Map.put(entry("gpt-6-astra"), "visibility", "hide"),
          entry("reserve-model"),
          entry("gpt-6-astra", ["unsupported-effort"]),
          entry("gpt-6-luna")
        ] do
      assert {:error, :catalog_insufficient_models} =
               ModelCatalog.decode(JSON.encode!(%{"models" => [entry("gpt-5.6-sol"), second]}))
    end
  end

  test "ambiguous and oversized metadata and forged snapshots fail closed" do
    for text <- [
          "{}",
          "[]",
          "invalid",
          <<255>>,
          String.duplicate(" ", 1_048_577),
          ~s({"models":[],"models":[]}),
          JSON.encode!(%{"models" => [entry("gpt-5.6-sol"), entry("gpt-5.6-sol")]}),
          JSON.encode!(%{
            "models" => [Map.put(entry("gpt-5.6-sol"), "supported_reasoning_levels", [])]
          })
        ] do
      assert {:error, :catalog_invalid} = ModelCatalog.decode(text)
    end

    {:ok, snapshot} = ModelCatalog.decode(catalog())

    for invalid <- [
          nil,
          Map.put(snapshot, "extra", "value"),
          Map.put(snapshot, "version", 1),
          Map.put(snapshot, "version", 2.0),
          Map.put(snapshot, "resolver", snapshot["primary"]),
          Map.put(snapshot, "primary", profile("reserve-model", "high")),
          Map.put(snapshot, "small", snapshot["primary"]),
          Map.put(snapshot, "fallbacks", []),
          Map.put(snapshot, "fallbacks", [snapshot["resolver"], snapshot["resolver"]]),
          Map.put(snapshot, "fallbacks", [profile("gpt-5.6-sol", "medium"), snapshot["resolver"]])
        ] do
      assert {:error, :catalog_invalid} = ModelCatalog.validate(invalid)
    end
  end

  test "routing uses only the saved catalog and preserves its exact capabilities" do
    {:ok, snapshot} = ModelCatalog.decode(catalog())
    assert ModelPolicy.current_routing() == 2
    assert ModelPolicy.current() == 1
    assert ModelPolicy.route(2, :plan, 0, nil, snapshot) == snapshot["primary"]

    assert ModelPolicy.route(2, :implement, 1, %{"complexity" => "small"}, snapshot) ==
             snapshot["small"]

    assert ModelPolicy.route(2, :resolve, 1, nil, snapshot) == snapshot["resolver"]
    assert ModelPolicy.route(2, :resolve, 2, nil, snapshot) == hd(snapshot["fallbacks"])
    assert ModelPolicy.route(2, :implement, 2, nil, snapshot) == snapshot["resolver"]
    assert ModelPolicy.route(2, :implement, 3, nil, snapshot) == hd(snapshot["fallbacks"])

    assert {:ok, profile("gpt-5.6-terra", "xhigh")} ==
             ModelPolicy.select(snapshot["primary"], ["gpt-5.6-sol"], snapshot)

    assert {:error, :models_exhausted} ==
             ModelPolicy.select(snapshot["primary"], ~w(gpt-5.6-sol gpt-5.6-terra), snapshot)

    assert {:ok, snapshot["small"]} ==
             ModelPolicy.select(snapshot["small"], ~w(gpt-5.6-sol gpt-5.6-terra), snapshot)

    assert {:error, :catalog_invalid} ==
             ModelPolicy.select(profile("gpt-6.1-sol", "high"), [], snapshot)

    assert_raise ArgumentError, fn -> ModelPolicy.route(2, :plan, 0, nil, %{}) end
    assert ModelPolicy.route(1, :plan, 0, nil, snapshot) == ModelPolicy.route(1, :plan, 0)
  end

  @tag skip: :os.type() != {:unix, :darwin}
  test "finite native metadata command uses a fresh cwd and requires clean success" do
    root = scratch()
    path = fixture(root, "success", "print(#{inspect(catalog())})")
    assert {:ok, snapshot} = ModelCatalog.discover(path)
    assert ModelCatalog.validate(snapshot) == :ok
    assert {:error, :catalog_unavailable} = ModelCatalog.discover(nil)

    failed = fixture(root, "failed", "print(#{inspect(catalog())})\nsys.exit(7)")
    assert {:error, :catalog_unavailable} = ModelCatalog.discover(failed)
    malformed = fixture(root, "malformed", "print('not json')")
    assert {:error, :catalog_invalid} = ModelCatalog.discover(malformed)
    oversized = fixture(root, "oversized", "print('x' * 1048577)")
    assert {:error, :catalog_unavailable} = ModelCatalog.discover(oversized)
  end

  @tag skip: :os.type() != {:unix, :darwin}
  test "Stop reaches the native metadata command and returns no catalog" do
    root = scratch()
    marker = Path.join(root, "started")

    path =
      fixture(
        root,
        "waiting",
        "pathlib.Path(#{inspect(marker)}).write_text('ready')\ntime.sleep(30)"
      )

    task = Task.async(fn -> ModelCatalog.discover(path) end)
    wait_file(marker, 200)
    send(task.pid, :stop)
    assert {:error, :cancelled} = Task.await(task, 5_000)
  end

  defp profile(model, effort), do: %{"model" => model, "reasoning_effort" => effort}

  defp entry(model, efforts \\ ~w(medium high xhigh)),
    do: %{
      "slug" => model,
      "visibility" => "list",
      "supported_reasoning_levels" => Enum.map(efforts, &%{"effort" => &1}),
      "description" => "SECRET_SENTINEL"
    }

  defp catalog,
    do:
      JSON.encode!(%{
        "models" => [
          entry("gpt-5.6-sol"),
          entry("gpt-5.6-terra"),
          entry("gpt-5.6-luna"),
          Map.put(entry("gpt-6-astra"), "visibility", "hide")
        ]
      })

  defp scratch do
    root = Path.join(System.tmp_dir!(), "boss-catalog-test-#{Ecto.UUID.generate()}")
    File.mkdir!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    root
  end

  defp fixture(root, name, body) do
    path = Path.join(root, name)

    File.write!(
      path,
      "#!/usr/bin/env python3\nimport sys, pathlib, time\nassert sys.argv[1:] == ['--config', 'model_provider=\"openai\"', 'debug', 'models']\nassert pathlib.Path.cwd().name.startswith('boss-model-catalog-')\nassert sys.stdin.read() == ''\n" <>
        body <> "\n"
    )

    File.chmod!(path, 0o700)
    path
  end

  defp wait_file(path, attempts) when attempts > 0 do
    unless File.exists?(path) do
      Process.sleep(10)
      wait_file(path, attempts - 1)
    end
  end

  defp wait_file(_, 0), do: flunk("metadata fixture did not start")
end
