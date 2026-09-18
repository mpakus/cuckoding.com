#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "json"
require "time"

STAGES = %w[specification development qa human_approval release_handoff].freeze

def truthy?(value)
  value == true
end

def validate(summary, stage_key:, outcome:)
  event = summary.fetch("reconciliation_events", []).first
  checks = {
    "stage_key" => summary["stage_key"] == stage_key,
    "sleep_gap" => truthy?(summary["detected_on_first_tick"]) && summary["detected_gap_ms"].to_i.positive?,
    "single_execution" => summary["stage_execution_count"] == 1,
    "single_reconciliation" => summary.fetch("reconciliation_events", []).length == 1,
    "outcome" => event&.fetch("outcome", nil) == outcome,
    "loopback_service" => truthy?(summary["dev_server_survived"]) && truthy?(summary["port_responded"]),
    "provider_stream" => truthy?(summary["provider_stream_reconnected"]),
    "worker" => outcome == "continued" ? truthy?(summary["worker_survived"]) : truthy?(summary["worker_recovered"]),
    "battery_lid" => outcome != "recovered" ||
      (summary["trigger"] == "lid_close" && summary["expected_power_source"] == "battery" &&
       !truthy?(summary.dig("power_before", "ac_attached")) &&
       !truthy?(summary.dig("power_after", "ac_attached")))
  }
  [checks, checks.values.all?]
end

evidence_root = File.expand_path(ARGV.fetch(0) do
  abort "usage: #{$PROGRAM_NAME} EVIDENCE_ROOT"
end)
physical_dir = File.join(evidence_root, "physical")
automated = JSON.parse(File.read(File.join(evidence_root, "automated", "summary.json")))

expectations = STAGES.map do |stage_key|
  ["real_sleep_#{stage_key}", "real-sleep-#{stage_key.tr("_", "-")}", stage_key, "continued"]
end
expectations << ["battery_lid_close", "lid-close-battery-recover-development", "development", "recovered"]

physical = expectations.map do |name, prefix, stage_key, outcome|
  summary_path = File.join(physical_dir, "#{prefix}-summary.json")
  pmset_path = File.join(physical_dir, "#{prefix}-pmset.log")
  clocks_path = File.join(physical_dir, "#{prefix}-clocks.json")
  errors = []

  begin
    summary = JSON.parse(File.read(summary_path))
    checks, passed = validate(summary, stage_key: stage_key, outcome: outcome)
    errors.concat(checks.filter_map { |key, ok| key unless ok })
  rescue Errno::ENOENT, JSON::ParserError => error
    passed = false
    errors << error.class.name
  end

  {"pmset" => pmset_path, "clocks" => clocks_path}.each do |kind, path|
    unless File.file?(path) && File.size?(path)
      passed = false
      errors << "missing_#{kind}"
    end
  end

  if outcome == "recovered" && File.file?(pmset_path) && !File.read(pmset_path).include?("Clamshell Sleep")
    passed = false
    errors << "missing_clamshell_sleep"
  end

  {
    "name" => name,
    "stage_key" => stage_key,
    "status" => passed ? "passed" : "failed",
    "errors" => errors,
    "summary" => File.basename(summary_path),
    "pmset_log" => File.basename(pmset_path),
    "clocks" => File.basename(clocks_path)
  }
end

automated_passed = automated.fetch("passed")
automated_total = automated.fetch("observations")
physical_passed = physical.count { |result| result.fetch("status") == "passed" }
total = automated_total + physical.length
passed = automated_passed + physical_passed
rate = (passed.fdiv(total) * 100).round(2)

summary = {
  "schema_version" => 1,
  "verified_at" => Time.now.utc.iso8601(6),
  "target_percent" => 95.0,
  "observations" => total,
  "passed" => passed,
  "failed" => total - passed,
  "recovery_percent" => rate,
  "target_met" => automated.fetch("target_met") && physical_passed == physical.length && rate >= 95.0,
  "automated_summary" => "automated/summary.json",
  "physical" => physical
}

FileUtils.mkdir_p(evidence_root)
File.write(File.join(evidence_root, "summary.json"), JSON.pretty_generate(summary) << "\n")
puts JSON.pretty_generate(summary)
exit(summary.fetch("target_met") ? 0 : 1)
