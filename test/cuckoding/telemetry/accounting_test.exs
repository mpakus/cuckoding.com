defmodule Cuckoding.Telemetry.AccountingTest do
  use Cuckoding.DataCase, async: false

  import Phoenix.LiveViewTest

  alias Cuckoding.Adapters.Types
  alias Cuckoding.Execution
  alias Cuckoding.Projects
  alias Cuckoding.Repo
  alias Cuckoding.Telemetry.Accounting
  alias Cuckoding.Telemetry.OptimizationRecord
  alias Cuckoding.Telemetry.UsageRecord
  alias Cuckoding.Workflows
  alias CuckodingWeb.UsageComponents

  @now ~U[2026-09-18 00:00:00.000000Z]

  test "provider-reported cost wins and replaying an event is idempotent" do
    domain = domain_fixture()
    catalog = publish_catalog()

    usage = %Types.Usage{
      source: "provider",
      confidence: "reported",
      input_tokens: 1_500,
      output_tokens: 500,
      cost_micros: 2_345,
      currency: "USD"
    }

    assert {:ok, record} =
             Accounting.record_usage(domain.session.id, "provider-turn-1", usage,
               billing_mode: :api,
               occurred_at: @now
             )

    assert record.source == "provider_reported"
    assert record.cost_source == "provider_reported"
    assert record.cost_micros == 2_345
    assert is_nil(record.price_catalog_version_id)
    assert is_nil(record.formula_json)
    refute record.event_key_hash == "provider-turn-1"
    assert Accounting.cost_label(record) == "$0.002345 USD"
    assert Accounting.cost_source_label(record) == "Provider-reported"

    replay = %{usage | cost_micros: 9_999}

    assert {:ok, same_record} =
             Accounting.record_usage(domain.session.id, "provider-turn-1", replay,
               billing_mode: :api,
               occurred_at: @now
             )

    assert same_record.id == record.id
    assert same_record.cost_micros == 2_345
    assert Repo.aggregate(UsageRecord, :count) == 1
    assert catalog.id != record.price_catalog_version_id
  end

  test "API usage reconciles exactly with the catalog effective at request time" do
    domain = domain_fixture()
    catalog = publish_catalog()

    assert {:ok, _future_catalog} =
             Accounting.publish_catalog(%{
               provider: "codex",
               version: 2,
               effective_from: DateTime.add(@now, 1, :second),
               source_uri: "fixture://codex-v2",
               catalog_json: %{
                 "currency" => "USD",
                 "models" => %{"gpt-test" => %{"input_micros_per_million" => 99_000_000}}
               }
             })

    usage = %Types.Usage{
      source: "provider",
      confidence: "reported",
      input_tokens: 1_500,
      output_tokens: 500,
      reasoning_tokens: 10,
      cache_read_tokens: 2_000,
      cache_write_tokens: 100
    }

    assert {:ok, record} =
             Accounting.record_usage(domain.session.id, "provider-turn-2", usage,
               billing_mode: :api,
               occurred_at: @now
             )

    assert record.cost_source == "catalog_estimate"
    assert record.cost_confidence == "catalog_estimate"
    assert record.price_catalog_version_id == catalog.id
    assert record.cost_micros == 13_125
    assert record.formula_json["denominator"] == 1_000_000
    assert record.formula_json["rounding"] == "nearest_micro_half_up"
    assert record.formula_json["total_numerator"] == 13_125_000_000
    assert length(record.formula_json["dimensions"]) == 5
    assert Accounting.cost_label(record) == "≈ $0.013125 USD"
    assert Accounting.cost_source_label(record) == "Catalog estimate"

    html = render_component(&UsageComponents.usage_summary/1, records: [record])
    assert html =~ "≈ $0.013125 USD"
    assert html =~ "Catalog estimate"
    assert html =~ "Provider cost is preferred"
    assert html =~ "1500 in · 500 out · 10 reasoning · 2000 cache read · 100 cache write"
  end

  test "subscription usage remains unavailable even when a matching catalog exists" do
    domain = domain_fixture()
    publish_catalog()

    usage = %Types.Usage{
      source: "provider",
      confidence: "reported",
      input_tokens: 1_000_000,
      output_tokens: 1_000_000
    }

    assert {:ok, record} =
             Accounting.record_usage(domain.session.id, "subscription-turn", usage,
               billing_mode: :subscription,
               occurred_at: @now
             )

    assert record.billing_mode == "subscription"
    assert record.cost_source == "unavailable"
    assert is_nil(record.cost_micros)
    assert is_nil(record.price_catalog_version_id)
    assert is_nil(record.formula_json)
    assert Accounting.cost_label(record) == "Cost unavailable"
  end

  test "catalog estimates round once to the nearest micro with halves rounded up" do
    domain = domain_fixture()

    assert {:ok, _catalog} =
             Accounting.publish_catalog(%{
               provider: "codex",
               version: 1,
               effective_from: DateTime.add(@now, -60, :second),
               source_uri: "fixture://rounding",
               catalog_json: %{
                 "currency" => "USD",
                 "models" => %{"gpt-test" => %{"input_micros_per_million" => 500_000}}
               }
             })

    usage = %Types.Usage{
      source: "provider",
      confidence: "reported",
      input_tokens: 1
    }

    assert {:ok, record} =
             Accounting.record_usage(domain.session.id, "rounding-half", usage,
               billing_mode: :api,
               occurred_at: @now
             )

    assert record.formula_json["total_numerator"] == 500_000
    assert record.cost_micros == 1
  end

  test "missing catalog rates do not produce a partial estimate" do
    domain = domain_fixture()

    assert {:ok, _catalog} =
             Accounting.publish_catalog(%{
               provider: "codex",
               version: 1,
               effective_from: DateTime.add(@now, -60, :second),
               source_uri: "fixture://incomplete",
               catalog_json: %{
                 "currency" => "USD",
                 "models" => %{"gpt-test" => %{"input_micros_per_million" => 3_000_000}}
               }
             })

    usage = %Types.Usage{
      source: "provider",
      confidence: "reported",
      input_tokens: 100,
      output_tokens: 100
    }

    assert {:ok, record} =
             Accounting.record_usage(domain.session.id, "missing-rate", usage,
               billing_mode: :api,
               occurred_at: @now
             )

    assert record.cost_source == "unavailable"
    assert is_nil(record.cost_micros)
  end

  test "usage remains attributable when the provider model is unknown" do
    domain = domain_fixture(nil)
    usage = %Types.Usage{source: "provider", confidence: "reported", input_tokens: 10}

    assert {:ok, record} =
             Accounting.record_usage(domain.session.id, "unknown-model", usage,
               billing_mode: :api,
               occurred_at: @now
             )

    assert is_nil(record.model)
    assert record.cost_source == "unavailable"

    html = render_component(&UsageComponents.usage_summary/1, records: [record])
    assert html =~ "codex/Unknown model"
  end

  test "plugin optimization claims remain a separate labeled dimension" do
    domain = domain_fixture()

    assert {:ok, optimization} =
             Accounting.record_optimization(
               %{
                 run_id: domain.run.id,
                 plugin_key: "rtk",
                 kind: "context_tokens",
                 raw_units: 1_000,
                 optimized_units: 650,
                 confidence: "estimated",
                 estimation_method: "plugin_reported_v1",
                 metadata_json: %{"command" => "mix test", "api_token" => "secret-canary"},
                 recorded_at: @now
               },
               redact: ["secret-canary"]
             )

    assert optimization.source == "plugin_reported"
    assert optimization.saved_units == 350
    assert optimization.metadata_json["api_token"] == "[REDACTED]"
    assert Accounting.optimization_label(optimization) == "≈ 350 saved"
    assert Repo.aggregate(OptimizationRecord, :count) == 1
    assert Repo.aggregate(UsageRecord, :count) == 0
  end

  test "catalogs reject floating or unknown rate fields" do
    assert {:error, changeset} =
             Accounting.publish_catalog(%{
               provider: "codex",
               version: 1,
               effective_from: @now,
               source_uri: "fixture://invalid",
               catalog_json: %{
                 "currency" => "USD",
                 "models" => %{"gpt-test" => %{"input_micros_per_million" => 0.5}}
               }
             })

    assert {"has invalid currency or model rates", _metadata} = changeset.errors[:catalog_json]
  end

  defp publish_catalog do
    {:ok, catalog} =
      Accounting.publish_catalog(%{
        provider: "codex",
        version: 1,
        effective_from: DateTime.add(@now, -60, :second),
        source_uri: "fixture://codex-v1",
        catalog_json: %{
          "currency" => "USD",
          "models" => %{
            "gpt-test" => %{
              "input_micros_per_million" => 3_000_000,
              "output_micros_per_million" => 15_000_000,
              "reasoning_micros_per_million" => 15_000_000,
              "cache_read_micros_per_million" => 300_000,
              "cache_write_micros_per_million" => 3_750_000
            }
          }
        }
      })

    catalog
  end

  defp domain_fixture(requested_model \\ "gpt-test") do
    suffix = System.unique_integer([:positive])

    {:ok, project} =
      Projects.register(%{
        name: "Accounting Project #{suffix}",
        repo_path: "/tmp/accounting-project-#{suffix}",
        default_branch: "main",
        workspace_root: "/tmp/accounting-workspaces-#{suffix}",
        port_range_start: 46_000,
        port_range_end: 46_100
      })

    {:ok, config} =
      Projects.add_config_version(%{
        project_id: project.id,
        revision: 1,
        source_hash: String.pad_leading(Integer.to_string(suffix, 16), 64, "0"),
        config_json: %{"version" => 1},
        trusted_at: @now
      })

    {:ok, workflow} =
      Workflows.publish_workflow(%{
        project_id: project.id,
        name: "default",
        version: 1,
        definition_json: %{"stages" => [%{"key" => "implementation", "role" => "implementer"}]},
        published_at: @now
      })

    {:ok, board} =
      Workflows.create_board(%{
        project_id: project.id,
        workflow_version_id: workflow.id,
        name: "Accounting Board #{suffix}",
        concurrency_limit: 1
      })

    {:ok, task} =
      Workflows.create_task(%{board_id: board.id, title: "Accounting task", position: 0})

    {:ok, run} =
      Execution.create_run(%{
        task_id: task.id,
        sequence: 1,
        policy_snapshot_id: config.id,
        plugin_snapshot_json: %{},
        branch: "feature/accounting-#{suffix}",
        base_sha: String.duplicate("a", 40)
      })

    {:ok, attempt} =
      Execution.create_stage_attempt(%{
        run_id: run.id,
        stage_key: "implementation",
        attempt: 1,
        role_key: "implementer",
        role_kind: "agent"
      })

    {:ok, session} =
      Execution.create_agent_session(%{
        stage_attempt_id: attempt.id,
        adapter_key: "codex",
        requested_model: requested_model,
        effective_grant_json: %{}
      })

    %{run: run, session: session}
  end
end
