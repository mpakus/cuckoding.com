# frozen_string_literal: true

require "minitest/autorun"
require_relative "power_manager_spike"

class PowerManagerSpikeTest < Minitest::Test
  Sample = PowerManagerSpike::Sample

  def test_detects_gap_from_continuous_and_uptime_divergence
    before = Sample.new(wall: 100.0, continuous: 200.0, uptime: 300.0)
    after = Sample.new(wall: 112.0, continuous: 212.0, uptime: 302.0)

    assert_equal 10_000, PowerManagerSpike.gap_ms(before, after)
  end

  def test_does_not_treat_wall_clock_change_as_sleep
    before = Sample.new(wall: 100.0, continuous: 200.0, uptime: 300.0)
    after = Sample.new(wall: 3_700.0, continuous: 202.0, uptime: 302.0)

    assert_nil PowerManagerSpike.gap_ms(before, after)
  end

  def test_does_not_treat_a_delayed_tick_as_sleep
    before = Sample.new(wall: 100.0, continuous: 200.0, uptime: 300.0)
    after = Sample.new(wall: 110.0, continuous: 210.0, uptime: 310.0)

    assert_nil PowerManagerSpike.gap_ms(before, after)
  end

  def test_reconciliation_is_idempotent_and_does_not_relaunch_live_stage
    run = run_state
    reconciler = PowerManagerSpike::Reconciler.new(now: -> { "2026-09-17T00:00:00.000000Z" })

    2.times do
      reconciler.reconcile(run, gap_id: "gap-1", gap_ms: 5_000,
        process_alive: ->(_process) { true }, recover: -> { flunk "must not recover" })
    end

    assert_equal 1, run.fetch("stage_execution_count")
    assert_equal 1, run.fetch("provider_session_count")
    assert_equal 1, run.fetch("events").length
    assert_equal "continued", run.fetch("events").first.fetch("outcome")
    assert_equal "2026-09-17T00:00:00.000000Z", run.fetch("events").first.fetch("occurred_at")
  end

  def test_dead_process_recovers_provider_without_relaunching_stage
    run = run_state

    PowerManagerSpike::Reconciler.new.reconcile(
      run,
      gap_id: "gap-2",
      gap_ms: 5_000,
      process_alive: ->(_process) { false },
      recover: -> { {"pid" => 22, "start_identity" => "replacement"} }
    )

    assert_equal 1, run.fetch("stage_execution_count")
    assert_equal 2, run.fetch("provider_session_count")
    assert_equal 22, run.dig("process", "pid")
    assert_equal "recovered", run.fetch("events").first.fetch("outcome")
  end

  def test_post_sleep_eof_is_transient
    assert_equal :transient,
      PowerManagerSpike.classify_stream_drop(EOFError.new, after_sleep: true)
    assert_equal :unclassified,
      PowerManagerSpike.classify_stream_drop(EOFError.new, after_sleep: false)
  end

  def test_sleep_log_keeps_only_current_cycle_events
    output = <<~LOG
      2026-09-17 11:12:17 -0500 Sleep old cycle
      2026-09-17 11:46:24 -0500 Assertions unrelated detail
      2026-09-17 11:46:34 -0500 Sleep current cycle
      2026-09-17 11:46:56 -0500 Wake current cycle
    LOG

    assert_equal <<~LOG, PowerManagerSpike.scoped_sleep_log(output, Time.new(2026, 9, 17, 11, 46, 24, "-05:00"))
      2026-09-17 11:46:34 -0500 Sleep current cycle
      2026-09-17 11:46:56 -0500 Wake current cycle
    LOG
  end

  def test_sleep_log_discards_malformed_bytes
    output = "2026-09-17 11:46:56 -0500 Wake current cycle\n\xFF".dup.force_encoding(Encoding::UTF_8)

    assert_equal "2026-09-17 11:46:56 -0500 Wake current cycle\n",
      PowerManagerSpike.scoped_sleep_log(output, Time.new(2026, 9, 17, 11, 46, 24, "-05:00"))
  end

  def test_lid_close_configuration_rejects_invalid_modes
    assert_raises(ArgumentError) do
      PowerManagerSpike::RealSleepVerifier.new(
        "evidence", stage_key: "development", lid_source: "usb"
      )
    end
    assert_raises(ArgumentError) do
      PowerManagerSpike::RealSleepVerifier.new(
        "evidence", stage_key: "development", worker_mode: "recover"
      )
    end
    assert_raises(ArgumentError) do
      PowerManagerSpike::RealSleepVerifier.new("evidence", stage_key: "unknown")
    end
  end

  def test_accepts_every_default_workflow_stage
    PowerManagerSpike::DEFAULT_STAGES.each do |stage_key|
      verifier = PowerManagerSpike::RealSleepVerifier.new("evidence", stage_key: stage_key)
      assert_equal stage_key, verifier.instance_variable_get(:@stage_key)
    end
  end

  private

  def run_state
    {
      "stage_execution_count" => 1,
      "provider_session_count" => 1,
      "process" => {"pid" => 11, "start_identity" => "original"},
      "reconciled_gap_ids" => [],
      "events" => []
    }
  end
end
