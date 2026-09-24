#!/usr/bin/ruby
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
load File.expand_path("../bin/dev.restart", __dir__)

class DeveloperRestartTest < Minitest::Test
  def setup
    @root = Dir.mktmpdir("Cuckoding restart test ")
    @app = File.join(File.realpath(@root), "Cuckoding.app")
    @shell = File.join(@app, "Contents/MacOS/cuckoding-shell")
    @beam = File.join(@app, "Contents/Resources/release/erts/bin/beam.smp")
    FileUtils.mkdir_p(File.dirname(@shell))
    File.write(@shell, "fixture")
    File.chmod(0o700, @shell)
    @signals = []
    @opens = []
    @listener = "n127.0.0.1:43210\n"
    @ps_status = 0
    @http = Net::HTTP.new("127.0.0.1", 43210, nil)
    @response = Struct.new(:code, :body).new("200", '{"status":"ok","application":{"name":"cuckoding"}}')
  end

  def teardown
    FileUtils.remove_entry(@root)
  end

  def row(pid, parent, executable, second = "01")
    "#{pid} #{parent} Thu Sep 24 12:00:#{second} 2026 #{executable}\n"
  end

  def execute(snapshots, timeout: false)
    last = nil
    clock = 0
    capture = lambda do |env, rtk, proxy, command, *args|
      assert_equal [{"LC_ALL" => "C"}, "rtk", "proxy"], [env, rtk, proxy]
      output, code = case command
                     when "/bin/ps"
                       assert_equal ["-ww", "-axo", "pid=,ppid=,lstart=,comm="], args
                       last = snapshots.shift || last
                       [last, @ps_status]
                     when "/usr/sbin/lsof" then [@listener, @listener.empty? ? 1 : 0]
                     when "/usr/bin/open"
                       @opens << args
                       ["", 0]
                     else flunk("Unexpected command #{command}")
                     end
      status = Minitest::Mock.new
      status.expect(:success?, code.zero?)
      status.expect(:exitstatus, code) unless code.zero?
      [output, "", status]
    end
    operation = lambda do |*|
      Open3.stub(:capture3, capture) do
        Process.stub(:kill, ->(*args) { @signals << args }) do
          Net::HTTP.stub(:new, @http) do
            @http.stub(:get, @response) { capture_io { DeveloperRestart.run(@app) } }
          end
        end
      end
    end
    if timeout
      Process.stub(:clock_gettime, ->(*) { clock += 31 }, &operation)
    else
      operation.call
    end
  end

  def test_restart_waits_for_descendants_and_preserves_unrelated_processes
    other = row(900, 1, "/Applications/Codex.app/Contents/MacOS/Codex")
    old = row(100, 1, @shell)
    children = row(101, 100, @beam) + row(102, 101, "/usr/local/bin/codex")
    stdout, = execute([old + children + other, old + children + other,
                       children + other, other, other,
                       row(200, 1, @shell) + row(201, 200, @beam) + other])
    assert_equal [["TERM", 100]], @signals
    assert_equal [[@app]], @opens
    assert_includes stdout, "http://127.0.0.1:43210"
  end

  def test_starts_when_stopped_and_refuses_missing_bundle
    idle = row(900, 1, "/bin/launchd")
    execute([idle, idle, row(200, 1, @shell) + row(201, 200, @beam)])
    assert_empty @signals
    assert_equal [[@app]], @opens
    File.delete(@shell)
    assert_raises(RuntimeError) { execute([]) }
    assert_equal [[@app]], @opens
  end

  def test_refuses_other_bundles_or_orphans_without_signalling_or_launching
    [row(100, 1, "/Applications/Cuckoding.app/Contents/MacOS/cuckoding-shell"),
     row(101, 1, @beam), row(100, 1, @shell) + row(200, 1, @shell)].each do |snapshot|
      assert_raises(RuntimeError) { execute([snapshot]) }
    end
    assert_empty @signals
    assert_empty @opens
  end

  def test_refuses_reused_pid_or_failed_process_inventory
    assert_raises(RuntimeError) { execute([row(100, 1, @shell), row(100, 1, @shell, "02")]) }
    @ps_status = 1
    assert_raises(RuntimeError) { execute([""]) }
    @ps_status = 0
    ["", "broken\n"].each { |snapshot| assert_raises(RuntimeError) { execute([snapshot]) } }
    assert_empty @signals
    assert_empty @opens
  end

  def test_shutdown_timeout_never_escalates_or_launches
    error = assert_raises(RuntimeError) { execute([row(100, 1, @shell)], timeout: true) }
    assert_includes error.message, "No force kill attempted"
    assert_equal [["TERM", 100]], @signals
    assert_empty @opens
  end

  def test_start_requires_loopback_and_healthy_cuckoding_response
    idle = row(900, 1, "/bin/launchd")
    running = row(200, 1, @shell) + row(201, 200, @beam)
    @listener = "n0.0.0.0:43210\n"
    assert_raises(RuntimeError) { execute([idle, idle, running]) }
    @listener = "n127.0.0.1:43210\n"
    @response.body = '{"status":"error"}'
    error = assert_raises(RuntimeError) { execute([idle, idle, running], timeout: true) }
    assert_includes error.message, "did not become healthy"
    assert_empty @signals
  end
end
