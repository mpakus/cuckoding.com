#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "json"
require "open3"
require "shellwords"
require "time"

ROOT = File.expand_path("../..", __dir__)

CASES = [
  ["reconciler", 4, %w[mix test test/cuckoding/reconciler_test.exs --only recovery_drill --seed 0]],
  ["power_manager", 3, %w[mix test test/cuckoding/power/manager_test.exs --only recovery_drill --seed 0]],
  ["hibernate_resume", 1, %w[mix test test/cuckoding/execution/lifecycle_test.exs --only recovery_drill --seed 0]],
  ["quit_hibernate", 1, %w[mix test test/cuckoding/shell_test.exs --only recovery_drill --seed 0]],
  ["single_release", 1, %w[mix test test/cuckoding/walking_skeleton_test.exs --only recovery_drill --seed 0]],
  ["power_contract", 9, %w[ruby spikes/0004-sleep-wake-power/test_power_manager_spike.rb]],
  ["safe_process_drill", 1,
   %w[ruby spikes/0004-sleep-wake-power/power_manager_spike.rb] + ["EVIDENCE_DIR"]]
].freeze

def parse_counts(output, fallback)
  if (match = output.match(/(?:(\d+) propert(?:y|ies), )?(\d+) tests?, (\d+) failures?/))
    [(match[1] || "0").to_i + match[2].to_i, match[3].to_i]
  elsif (match = output.match(/(\d+) runs, .*?(\d+) failures, (\d+) errors/))
    [match[1].to_i, match[2].to_i + match[3].to_i]
  else
    [fallback, nil]
  end
end

output_arg = ARGV.fetch(0) do
  abort "usage: #{$PROGRAM_NAME} OUTPUT_DIR"
end
output_dir = File.expand_path(output_arg)
FileUtils.mkdir_p(output_dir)
started_at = Time.now.utc

results = CASES.map do |name, expected, raw_command|
  case_evidence = File.join(output_dir, name)
  case_evidence_arg = File.join(output_arg, name)
  FileUtils.mkdir_p(case_evidence)
  command = raw_command.map { |part| part == "EVIDENCE_DIR" ? case_evidence_arg : part }
  wrapped = ["rtk", "proxy", *command]
  before = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  stdout, stderr, status = Open3.capture3({"MIX_ENV" => "test"}, *wrapped, chdir: ROOT)
  duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - before) * 1000).round
  log = "$ #{wrapped.shelljoin}\n#{stdout}#{stderr}"
  File.write(File.join(output_dir, "#{name}.log"), log)
  observed, failures = parse_counts(log, expected)
  failures = status.success? ? 0 : expected if failures.nil?
  failures += (expected - observed).abs if observed != expected

  {
    "name" => name,
    "expected_observations" => expected,
    "observed" => observed,
    "failures" => failures,
    "status" => status.success? && observed == expected && failures.zero? ? "passed" : "failed",
    "duration_ms" => duration_ms,
    "command" => wrapped.shelljoin,
    "log" => "#{name}.log"
  }
end

observations = results.sum { |result| result.fetch("expected_observations") }
failures = results.sum { |result| result.fetch("failures") }
passed = observations - failures
rate = observations.zero? ? 0.0 : (passed.fdiv(observations) * 100).round(2)
summary = {
  "schema_version" => 1,
  "started_at" => started_at.iso8601(6),
  "completed_at" => Time.now.utc.iso8601(6),
  "target_percent" => 95.0,
  "observations" => observations,
  "passed" => passed,
  "failed" => failures,
  "recovery_percent" => rate,
  "target_met" => rate >= 95.0 && results.all? { |result| result.fetch("status") == "passed" },
  "cases" => results
}
File.write(File.join(output_dir, "summary.json"), JSON.pretty_generate(summary) << "\n")
puts JSON.pretty_generate(summary)
exit(summary.fetch("target_met") ? 0 : 1)
