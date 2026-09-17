#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "json"
require "open3"
require "time"

module PowerManagerSpike
  TOLERANCE_SECONDS = 1.0
  SAFE_PATH = "/usr/bin:/bin:/usr/sbin:/sbin"

  Sample = Data.define(:wall, :continuous, :uptime)

  module_function

  def sample
    Sample.new(
      wall: Time.now.to_f,
      continuous: Process.clock_gettime(Process::CLOCK_MONOTONIC),
      uptime: Process.clock_gettime(Process::CLOCK_UPTIME_RAW)
    )
  end

  def gap_ms(previous, current, tolerance: TOLERANCE_SECONDS)
    continuous_elapsed = current.continuous - previous.continuous
    uptime_elapsed = current.uptime - previous.uptime
    gap = continuous_elapsed - uptime_elapsed
    gap > tolerance ? (gap * 1000).round : nil
  end

  def process_alive?(pid)
    Process.kill(0, pid)
    state, status = Open3.capture2("/bin/ps", "-o", "state=", "-p", pid.to_s)
    status.success? && !state.strip.start_with?("Z")
  rescue Errno::ESRCH
    false
  end

  def process_start_identity(pid)
    output, status = Open3.capture2("/bin/ps", "-o", "lstart=", "-p", pid.to_s)
    status.success? ? output.strip : nil
  end

  class Assertion
    attr_reader :pid

    def hold(owner_pid)
      raise "assertion already held" if @pid

      @pid = Process.spawn(
        {"PATH" => SAFE_PATH},
        "/usr/bin/caffeinate", "-i", "-w", owner_pid.to_s,
        out: File::NULL, err: File::NULL, pgroup: true, unsetenv_others: true
      )
    end

    def release
      return unless @pid

      return if Process.waitpid2(@pid, Process::WNOHANG)

      Process.kill("TERM", @pid)
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 1
      until Process.waitpid2(@pid, Process::WNOHANG)
        break if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline

        sleep 0.05
      end
      Process.kill("KILL", @pid) if PowerManagerSpike.process_alive?(@pid)
      Process.wait(@pid)
    rescue Errno::ESRCH, Errno::ECHILD
      nil
    ensure
      @pid = nil
    end
  end

  class Reconciler
    def initialize(now: -> { Time.now.utc.iso8601(6) })
      @now = now
    end

    def reconcile(run, gap_id:, gap_ms:, process_alive:, recover:)
      return run if run.fetch("reconciled_gap_ids", []).include?(gap_id)

      if process_alive.call(run.fetch("process"))
        outcome = "continued"
      else
        run["process"] = recover.call
        run["provider_session_count"] = run.fetch("provider_session_count") + 1
        outcome = "recovered"
      end

      run["reconciled_gap_ids"] = run.fetch("reconciled_gap_ids", []) + [gap_id]
      run["events"] << {
        "type" => "run.resumed_after_sleep",
        "gap_id" => gap_id,
        "gap_ms" => gap_ms,
        "outcome" => outcome,
        "occurred_at" => @now.call
      }
      run
    end
  end

  def classify_stream_drop(error, after_sleep:)
    transient = error.is_a?(EOFError) || error.is_a?(Errno::ECONNRESET) ||
      error.is_a?(Errno::ETIMEDOUT)
    transient && after_sleep ? :transient : :unclassified
  end

  class Verifier
    def initialize(evidence_dir)
      @evidence_dir = File.expand_path(evidence_dir)
      @owned_pids = []
    end

    def run
      FileUtils.mkdir_p(@evidence_dir)
      before_assertions = assertions

      owner = spawn_worker
      assertion = Assertion.new
      assertion_pid = assertion.hold(owner.fetch("pid"))
      wait_for("caffeinate assertion to appear") { assertion_present?(assertion_pid) }
      active_assertions = assertions

      assertion.release
      wait_for("caffeinate assertion to disappear") { !assertion_present?(assertion_pid) }
      owner_alive_after_release = PowerManagerSpike.process_alive?(owner.fetch("pid"))
      after_assertions = assertions
      write("assertions-before.txt", assertion_evidence(before_assertions, assertion_pid))
      write("assertions-active.txt", assertion_evidence(active_assertions, assertion_pid))
      write("assertions-after.txt", assertion_evidence(after_assertions, assertion_pid))

      gap = PowerManagerSpike.gap_ms(
        Sample.new(wall: 1_000.0, continuous: 2_000.0, uptime: 3_000.0),
        Sample.new(wall: 1_012.0, continuous: 2_012.0, uptime: 3_002.0)
      )
      raise "expected 10 second simulated gap, got #{gap.inspect}" unless gap == 10_000

      run_state = {
        "stage_key" => "development",
        "stage_execution_count" => 1,
        "provider_session_count" => 1,
        "process" => owner,
        "reconciled_gap_ids" => [],
        "events" => []
      }
      reconciler = Reconciler.new
      alive = lambda do |record|
        PowerManagerSpike.process_alive?(record.fetch("pid")) &&
          PowerManagerSpike.process_start_identity(record.fetch("pid")) == record.fetch("start_identity")
      end
      recover = -> { spawn_worker }

      reconciler.reconcile(run_state, gap_id: "simulated-live", gap_ms: gap,
        process_alive: alive, recover: recover)
      reconciler.reconcile(run_state, gap_id: "simulated-live", gap_ms: gap,
        process_alive: alive, recover: recover)

      owner_exit_assertion_pid = assertion.hold(owner.fetch("pid"))
      wait_for("owner-exit assertion to appear") { assertion_present?(owner_exit_assertion_pid) }
      stop(owner.fetch("pid"))
      wait_for("owner-exit assertion to disappear") { !assertion_present?(owner_exit_assertion_pid) }
      assertion.release
      reconciler.reconcile(run_state, gap_id: "simulated-dead", gap_ms: gap,
        process_alive: alive, recover: recover)

      raise "stage executed more than once" unless run_state.fetch("stage_execution_count") == 1
      raise "expected one provider recovery" unless run_state.fetch("provider_session_count") == 2
      raise "duplicate reconciliation event" unless run_state.fetch("events").length == 2

      stream_class = PowerManagerSpike.classify_stream_drop(EOFError.new, after_sleep: true)
      raise "stream drop was not transient" unless stream_class == :transient

      summary = {
        "assertion" => {
          "pid" => assertion_pid,
          "visible_while_active" => true,
          "released_while_owner_alive" => owner_alive_after_release,
          "released_when_owner_exited" => true
        },
        "simulated_gap_ms" => gap,
        "stage_execution_count" => run_state.fetch("stage_execution_count"),
        "provider_session_count" => run_state.fetch("provider_session_count"),
        "provider_stream_drop" => stream_class.to_s,
        "events" => run_state.fetch("events"),
        "real_sleep_test" => "pending_human_coordination",
        "lid_close_ac_test" => "pending_human_coordination",
        "lid_close_battery_test" => "pending_human_coordination"
      }
      write("timeline.json", JSON.pretty_generate(run_state) << "\n")
      write("summary.json", JSON.pretty_generate(summary) << "\n")
      puts JSON.pretty_generate(summary)
    ensure
      assertion&.release
      @owned_pids.each { |pid| stop(pid) }
    end

    private

    def spawn_worker
      pid = Process.spawn(
        {"PATH" => SAFE_PATH}, "/bin/sleep", "60",
        out: File::NULL, err: File::NULL, pgroup: true, unsetenv_others: true
      )
      @owned_pids << pid
      {
        "pid" => pid,
        "pgid" => Process.getpgid(pid),
        "start_identity" => PowerManagerSpike.process_start_identity(pid)
      }
    end

    def stop(pid)
      return unless PowerManagerSpike.process_alive?(pid)

      Process.kill("TERM", -Process.getpgid(pid))
      Process.wait(pid)
    rescue Errno::ESRCH, Errno::ECHILD
      nil
    ensure
      @owned_pids.delete(pid)
    end

    def assertions
      output, status = Open3.capture2e("/usr/bin/pmset", "-g", "assertions")
      raise "pmset assertions failed: #{output}" unless status.success?

      output
    end

    def assertion_present?(pid)
      assertions.include?("pid #{pid}(caffeinate)")
    end

    def assertion_evidence(output, pid)
      lines = output.lines
      index = lines.index { |line| line.include?("pid #{pid}(caffeinate)") }
      matches = index ? lines.slice(index, 2) : []
      [
        "source: /usr/bin/pmset -g assertions",
        "target_pid: #{pid}",
        "target_present: #{output.include?("pid #{pid}(caffeinate)")}",
        *matches.map(&:strip),
        ""
      ].join("\n")
    end

    def wait_for(description)
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 3
      until yield
        raise "timed out waiting for #{description}" if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline

        sleep 0.05
      end
    end

    def write(name, contents)
      File.write(File.join(@evidence_dir, name), contents)
    end
  end
end

if $PROGRAM_NAME == __FILE__
  abort "usage: #{$PROGRAM_NAME} EVIDENCE_DIR" unless ARGV.one?

  PowerManagerSpike::Verifier.new(ARGV.fetch(0)).run
end
