#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "net/http"
require "securerandom"
require "socket"
require "tmpdir"
require "time"

ROOT = File.expand_path(__dir__)
RELEASE = File.join(ROOT, "control_plane/_build/prod/rel/cuckoding_shell_spike/bin/cuckoding_shell_spike")
SAFE_PATH = "/usr/bin:/bin:/usr/sbin:/sbin"

def assert(condition, message)
  raise message unless condition
  puts "#{Time.now.utc.iso8601(3)} PASS #{message}"
end

def free_port
  server = TCPServer.new("127.0.0.1", 0)
  server.local_address.ip_port
ensure
  server&.close
end

def spawn_release(extra_env = {})
  directory = Dir.mktmpdir("cuckoding-shell-spike-")
  token_path = File.join(directory, "bootstrap-token")
  bootstrap = SecureRandom.hex(32)
  File.write(token_path, "#{SecureRandom.hex(64)}\n#{bootstrap}", mode: "w", perm: 0o600)
  reader, writer = IO.pipe
  port = free_port
  env = {
    "PATH" => SAFE_PATH,
    "HOME" => directory,
    "LANG" => "en_US.UTF-8",
    "RELEASE_DISTRIBUTION" => "none",
    "CUCKODING_PORT" => port.to_s,
    "CUCKODING_BOOTSTRAP_FILE" => token_path
  }.merge(extra_env)
  started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  pid = Process.spawn(env, RELEASE, "start", out: writer, err: writer, pgroup: true, unsetenv_others: true)
  writer.close
  {pid: pid, output: reader, port: port, bootstrap: bootstrap, token_path: token_path, directory: directory, started_at: started_at}
end

def wait_ready(run, timeout: 15)
  deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
  while (remaining = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)).positive?
    next unless IO.select([run[:output]], nil, nil, remaining)
    line = run[:output].gets
    break unless line
    next unless line.start_with?("READY ")

    payload = JSON.parse(line.delete_prefix("READY "))
    if payload == {"port" => run[:port], "version" => "0.1.0"}
      run[:ready_seconds] = Process.clock_gettime(Process::CLOCK_MONOTONIC) - run[:started_at]
      return payload
    end
    raise "READY payload mismatch: #{payload.inspect}"
  end
  raise "release did not emit exact READY payload"
end

def request(run, method, path, token: nil, cookie: nil, host: nil)
  http = Net::HTTP.new("127.0.0.1", run[:port])
  request = Net::HTTPGenericRequest.new(method, false, true, path)
  request["Authorization"] = "Bearer #{token}" if token
  request["Cookie"] = cookie if cookie
  request["Host"] = host if host
  http.request(request)
end

def wait_exit(run, timeout: 8)
  deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
  loop do
    result = Process.waitpid2(run[:pid], Process::WNOHANG)
    return result.last if result
    raise "process #{run[:pid]} did not exit" if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
    sleep 0.05
  end
end

def group_alive?(pid)
  Process.kill(0, -pid)
  true
rescue Errno::ESRCH
  false
end

def cleanup(run)
  Process.kill("KILL", -run[:pid]) if group_alive?(run[:pid])
  Process.waitpid(run[:pid])
rescue Errno::ESRCH, Errno::ECHILD
  nil
ensure
  run[:output]&.close
  FileUtils.remove_entry(run[:directory]) if run[:directory] && File.exist?(run[:directory])
end

require "fileutils"

raise "release missing; run the build first" unless File.executable?(RELEASE)

run = spawn_release
begin
  assert(wait_ready(run), format("release emits exact READY JSON in %.3fs", run[:ready_seconds]))
  assert(!File.exist?(run[:token_path]), "bootstrap file is deleted after startup")
  assert(request(run, "GET", "/", host: "localhost").code == "400", "non-loopback Host header is rejected")
  assert(request(run, "POST", "/shell/bootstrap").code == "401", "missing bootstrap token is rejected")
  assert(request(run, "POST", "/shell/bootstrap", token: "invalid").code == "401", "invalid bootstrap token is rejected")

  bootstrap_response = request(run, "POST", "/shell/bootstrap", token: run[:bootstrap])
  shell_token = JSON.parse(bootstrap_response.body).fetch("shell_token")
  assert(bootstrap_response.code == "200" && !shell_token.empty?, "bootstrap token is exchanged once")
  assert(request(run, "POST", "/shell/bootstrap", token: run[:bootstrap]).code == "401", "bootstrap replay is rejected")
  assert(request(run, "GET", "/shell/status").code == "401", "missing shell token is rejected")
  assert(request(run, "GET", "/shell/status", token: "invalid").code == "401", "invalid shell token is rejected")

  status = request(run, "GET", "/shell/status", token: shell_token)
  assert(status.code == "200" && JSON.parse(status.body) == {"active_runs" => 0, "attention" => 0}, "authenticated shell status is available")

  browser_token_response = request(run, "POST", "/shell/tokens", token: shell_token)
  browser_token = JSON.parse(browser_token_response.body).fetch("token")
  assert(browser_token_response.code == "200", "shell can mint a short-lived browser token")

  open_path = "/open?token=#{browser_token}&next=/settings"
  open_response = request(run, "GET", open_path)
  cookie = open_response["set-cookie"]&.split(";")&.first
  expected_redirect = open_response["location"]&.end_with?("/settings")
  assert(
    open_response.code == "302" && expected_redirect && cookie,
    "browser token creates a session for the requested safe path " \
      "(code=#{open_response.code}, location=#{open_response["location"].inspect}, cookie=#{!cookie.nil?})"
  )
  assert(request(run, "GET", open_path).code == "401", "browser token replay is rejected")
  assert(request(run, "GET", "/open?token=invalid").code == "401", "invalid browser token is rejected")

  unsafe_token_response = request(run, "POST", "/shell/tokens", token: shell_token)
  unsafe_token = JSON.parse(unsafe_token_response.body).fetch("token")
  unsafe_redirect = request(run, "GET", "/open?token=#{unsafe_token}&next=https://example.com")
  assert(unsafe_redirect.code == "302" && unsafe_redirect["location"] == "/", "browser handoff rejects an external redirect target")

  page = request(run, "GET", "/settings", cookie: cookie)
  assert(page.code == "200" && page.body.include?("Authenticated LiveView shell spike."), "authenticated LiveView renders")
  assert(request(run, "GET", "/").code == "302", "unauthenticated LiveView redirects")

  crash_started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  assert(request(run, "POST", "/shell/crash", token: shell_token).code == "200", "authenticated crash injection is accepted")
  assert(wait_exit(run).exitstatus == 42, "post-readiness crash exits with the injected status")
  assert(Process.clock_gettime(Process::CLOCK_MONOTONIC) - crash_started < 2, "post-readiness crash is detected within 2s")
  sleep 0.2
  assert(!group_alive?(run[:pid]), "post-readiness crash leaves no process-group descendants")
ensure
  cleanup(run)
end

run = spawn_release
begin
  wait_ready(run)
  shell_token = JSON.parse(request(run, "POST", "/shell/bootstrap", token: run[:bootstrap]).body).fetch("shell_token")
  shutdown_started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  assert(request(run, "POST", "/shell/shutdown", token: shell_token).code == "200", "authenticated graceful shutdown is accepted")
  assert(wait_exit(run).success?, "graceful shutdown exits successfully")
  assert(Process.clock_gettime(Process::CLOCK_MONOTONIC) - shutdown_started < 3, "graceful shutdown completes within 3s")
  sleep 0.2
  assert(!group_alive?(run[:pid]), "graceful shutdown leaves no process-group descendants")
ensure
  cleanup(run)
end

run = spawn_release("CUCKODING_CRASH_BEFORE_READY" => "1")
begin
  status = wait_exit(run)
  output = run[:output].read
  assert(status.exitstatus == 41 && !output.include?("READY "), "pre-readiness crash exits without a false READY signal")
  assert(Process.clock_gettime(Process::CLOCK_MONOTONIC) - run[:started_at] < 2, "pre-readiness crash is detected within 2s")
  sleep 0.2
  assert(!group_alive?(run[:pid]), "pre-readiness crash leaves no process-group descendants")
ensure
  cleanup(run)
end
