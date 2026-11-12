defmodule Boss.AgentModelDiscoveryTest do
  use ExUnit.Case, async: true

  alias Boss.Agents.{Authorizer, Metadata, ModelDiscovery}

  test "Codex deduplicates visible IDs and handles malformed optional model fields" do
    entry = %{
      "slug" => "gpt-6.1-sol",
      "visibility" => "list",
      "display_name" => %{"unexpected" => "value"},
      "supported_reasoning_levels" => "invalid",
      "default_reasoning_level" => "xhigh"
    }

    assert {:ok, [model]} =
             ModelDiscovery.parse_codex_models(
               Jason.encode!(%{"models" => [entry, entry, %{"visibility" => "hide"}]})
             )

    assert model["name"] == entry["slug"]
    assert model["reasoning_efforts"] == []
    assert model["default_effort"] == nil
  end

  test "Cursor publishes the exact variant ID and no independent effort levels" do
    assert {:ok, [model]} =
             ModelDiscovery.parse_cursor_models("gpt-6.1-sol-high - GPT-6.1 Sol High\n")

    assert model["id"] == "gpt-6.1-sol-high"
    assert model["reasoning"]
    assert model["reasoning_efforts"] == []
    assert {:error, :invalid_models} = ModelDiscovery.parse_cursor_models("Unexpected message")
    assert {:error, :invalid_models} = ModelDiscovery.parse_cursor_models(<<255>>)
  end

  test "OpenCode keeps distinct regional models, parses braces in model names and skips no rows by position" do
    items =
      for i <- 1..65 do
        id = "us.vendor-model-#{i}"
        header = "amazon-bedrock/#{id}"
        json = Jason.encode!(%{"id" => id, "name" => "Model {#{i}", "capabilities" => "bad"})
        header <> "\n" <> json <> "\n"
      end

    assert {:ok, models} = ModelDiscovery.parse_opencode_models(IO.iodata_to_binary(items))
    assert length(models) == 65
    assert List.last(models)["id"] == "amazon-bedrock/us.vendor-model-65"
    assert List.last(models)["name"] == "Model {65"
    assert {:error, :invalid_models} = ModelDiscovery.parse_opencode_models(<<255>>)
  end

  test "a failed refresh keeps local auth and carries a fixed diagnostic" do
    row = %{Metadata.new(:codex, "/tmp/fake-codex") | probe_status: :ok, auth_status: :configured}

    assert %{auth_status: :configured, errors: [%{stage: :models, reason: :invalid_models}]} =
             enriched = Authorizer.enrich(row, __MODULE__.InvalidCatalog)

    refute Map.has_key?(enriched, :models)
  end

  defmodule InvalidCatalog do
    def fetch(:codex, _path), do: {:error, :invalid_models}
  end

  @tag skip: :os.type() != {:unix, :darwin}
  test "native metadata connects Pi, Hermes and OpenCode through their local model surfaces" do
    pi =
      fixture("pi", """
      [ "$*" = "--no-extensions --list-models" ] || exit 64
      [ "$PI_OFFLINE" = "1" ] || exit 64
      printf '%s\\n' 'provider  model              context  max-out  thinking  images' \\
        'openai    gpt-5.5            1.1M     64K      yes       yes'
      """)

    assert %{auth_status: :configured, models: [model]} = enrich(:pi, pi)
    assert model["id"] == "openai/gpt-5.5"
    assert model["context_window"] == 1_100_000
    assert model["reasoning"]
    assert model["reasoning_efforts"] == []

    hermes =
      fixture("hermes", """
      case "$*" in
        'status --help') printf '%s\\n' 'options:' '  --full    print every section' ;;
        'status') printf '%s\\n' '  Model:         anthropic/claude-sonnet-4.6' \\
          '  Provider:      OpenRouter' '  Providers:     OpenRouter, Anthropic' ;;
        *) exit 64 ;;
      esac
      """)

    assert %{auth_status: :configured, models: [%{"id" => "anthropic/claude-sonnet-4.6"}]} =
             enrich(:hermes, hermes)

    opencode =
      fixture("opencode", """
      [ "$*" = "--pure models --verbose" ] || exit 64
      printf '%s\\n' 'openai/gpt-5.5' '{"id":"gpt-5.5","name":"GPT-5.5"}'
      """)

    assert %{auth_status: :configured, models: [%{"id" => "openai/gpt-5.5"}]} =
             enrich(:opencode, opencode)
  end

  @tag skip: :os.type() != {:unix, :darwin}
  test "native catalogs leave unrecognized sign-in unknown and older Hermes status untouched" do
    pi =
      fixture("pi", """
      printf '%s\\n' 'No models available. Use /login to log into a provider via OAuth or API key.'
      """)

    assert %{auth_status: :unknown} = enriched = enrich(:pi, pi)
    refute Map.has_key?(enriched, :models)

    hermes =
      fixture("hermes", """
      [ "$*" = "status --help" ] || exit 64
      printf '%s\\n' 'options:' '  --deep    query endpoint'
      """)

    assert %{auth_status: :unknown, errors: [%{stage: :models, reason: :unavailable}]} =
             enrich(:hermes, hermes)
  end

  @tag skip: :os.type() != {:unix, :darwin}
  test "Claude catalog uses advertised efforts and never invokes auth a second time" do
    claude =
      fixture("claude", """
      [ "$*" = "--help" ] || exit 64
      printf '%s\\n' '  --effort <level>     Effort level for the current session (low, high)'
      """)

    row = %{Metadata.new(:claude, claude) | probe_status: :ok, auth_status: :configured}
    assert %{auth_status: :configured, models: models} = Authorizer.enrich(row, ModelDiscovery)
    assert Enum.find(models, &(&1["id"] == "opus"))["reasoning_efforts"] == ["low", "high"]

    assert Enum.find(models, &(&1["id"] == "claude-haiku-4-5-20251001"))["reasoning_efforts"] ==
             []
  end

  @tag skip: :os.type() != {:unix, :darwin}
  test "Codex and Cursor catalog commands use exact argv and retain no raw output" do
    codex =
      fixture("codex", """
      [ "$*" = '--config model_provider="openai" debug models' ] || exit 64
      printf '%s\\n' '{"models":[{"slug":"gpt-6.1-sol","visibility":"list","secret":"IGNORE_ME"}]}'
      """)

    row = %{Metadata.new(:codex, codex) | probe_status: :ok, auth_status: :configured}

    assert %{models: [%{"id" => "gpt-6.1-sol"}]} =
             enriched = Authorizer.enrich(row, ModelDiscovery)

    refute inspect(enriched) =~ "IGNORE_ME"

    cursor =
      fixture("cursor", """
      [ "$*" = "models" ] || exit 64
      printf '%s\\n' 'Authentication required. Please sign in. IGNORE_ME' >&2
      exit 1
      """)

    row = %{Metadata.new(:cursor, cursor) | probe_status: :ok, auth_status: :configured}
    assert %{auth_status: :stale} = enriched = Authorizer.enrich(row, ModelDiscovery)
    refute Map.has_key?(enriched, :models)
    refute inspect(enriched) =~ "IGNORE_ME"
  end

  test "terminal login starts the interactive provider selection supported by each CLI" do
    assert Authorizer.login_argv(:pi) == []
    assert Authorizer.login_argv(:hermes) == ["model"]
    assert Authorizer.login_argv(:opencode) == ["auth", "login"]
  end

  defp enrich(id, path) do
    Authorizer.enrich(%{Metadata.new(id, path) | probe_status: :ok}, ModelDiscovery)
  end

  defp fixture(name, body) do
    root = Path.join(System.tmp_dir!(), "boss-model-discovery-test-#{Ecto.UUID.generate()}")
    File.mkdir!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    path = Path.join(root, name)

    File.write!(path, """
    #!/bin/sh
    case "$PWD" in */boss-agent-models-*) ;; *) exit 65 ;; esac
    #{body}
    """)

    File.chmod!(path, 0o700)
    path
  end
end
