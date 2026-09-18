#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "json"
require "net/http"
require "securerandom"
require "socket"
require "tmpdir"
require "time"

ROOT = File.expand_path(__dir__)
RELEASE = File.join(ROOT, "release/bin/cuckoding")
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

def release_env(directory, token_path, port)
  {
    "PATH" => SAFE_PATH,
    "HOME" => directory,
    "LANG" => "en_US.UTF-8",
    "PHX_SERVER" => "true",
    "RELEASE_DISTRIBUTION" => "none",
    "CUCKODING_PORT" => port.to_s,
    "CUCKODING_DATABASE_PATH" => File.join(directory, "cuckoding.sqlite3"),
    "CUCKODING_BOOTSTRAP_FILE" => token_path
  }
end

def spawn_release
  directory = Dir.mktmpdir("cuckoding-shell-")
  token_path = File.join(directory, "bootstrap")
  bootstrap = SecureRandom.hex(32)
  File.write(token_path, "#{SecureRandom.hex(64)}\n#{bootstrap}", mode: "w", perm: 0o600)
  port = free_port
  env = release_env(directory, token_path, port)

  migrated = Process.spawn(
    env,
    RELEASE,
    "eval",
    "Cuckoding.Release.migrate()",
    out: File::NULL,
    err: File::NULL,
    unsetenv_others: true
  )
  _, migration_status = Process.waitpid2(migrated)
  raise "release migration failed" unless migration_status.success?

  reader, writer = IO.pipe
  started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  pid = Process.spawn(
    env,
    RELEASE,
    "start",
    out: writer,
    err: writer,
    pgroup: true,
    unsetenv_others: true
  )
  writer.close

  {
    pid: pid,
    output: reader,
    port: port,
    bootstrap: bootstrap,
    token_path: token_path,
    directory: directory,
    started_at: started_at
  }
end

def spawn_pre_ready_failure
  directory = Dir.mktmpdir("cuckoding-shell-failure-")
  token_path = File.join(directory, "bootstrap")
  bootstrap = SecureRandom.hex(32)
  File.write(token_path, "#{SecureRandom.hex(64)}\n#{bootstrap}", mode: "w", perm: 0o600)
  reader, writer = IO.pipe
  port = free_port
  env = release_env(directory, token_path, port)
  env["CUCKODING_DATABASE_PATH"] = "/dev/null/cuckoding.sqlite3"
  started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  pid = Process.spawn(
    env,
    RELEASE,
    "start",
    out: writer,
    err: writer,
    pgroup: true,
    unsetenv_others: true
  )
  writer.close

  {
    pid: pid,
    output: reader,
    port: port,
    bootstrap: bootstrap,
    token_path: token_path,
    directory: directory,
    started_at: started_at
  }
end

def wait_ready(run, timeout: 15)
  deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout

  while (remaining = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)).positive?
    next unless IO.select([run[:output]], nil, nil, remaining)

    line = run[:output].gets
    break unless line
    next unless line.start_with?("READY ")

    payload = JSON.parse(line.delete_prefix("READY "))
    expected = {"port" => run[:port], "version" => "0.1.0"}
    raise "READY payload mismatch: #{payload.inspect}" unless payload == expected

    run[:ready_seconds] = Process.clock_gettime(Process::CLOCK_MONOTONIC) - run[:started_at]
    return payload
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

raise "release missing; run desktop/build.sh first" unless File.executable?(RELEASE)

run = spawn_release
begin
  assert(wait_ready(run), format("sterile release emits READY in %.3fs", run[:ready_seconds]))
  assert(!File.exist?(run[:token_path]), "bootstrap file is deleted after startup")
  assert(request(run, "GET", "/shell/status", host: "localhost").code == "403", "non-loopback Host is rejected")
  assert(request(run, "POST", "/shell/bootstrap").code == "401", "missing bootstrap token is rejected")
  assert(request(run, "POST", "/shell/bootstrap", token: "invalid").code == "401", "invalid bootstrap token is rejected")

  bootstrap_response = request(run, "POST", "/shell/bootstrap", token: run[:bootstrap])
  shell_token = JSON.parse(bootstrap_response.body).fetch("shell_token")
  assert(bootstrap_response.code == "200", "bootstrap token is exchanged once")
  assert(request(run, "POST", "/shell/bootstrap", token: run[:bootstrap]).code == "401", "bootstrap replay is rejected")
  assert(request(run, "GET", "/shell/status").code == "401", "missing shell token is rejected")

  status = request(run, "GET", "/shell/status", token: shell_token)
  assert(status.code == "200" && JSON.parse(status.body) == {"active_runs" => 0, "attention" => 0}, "shell status is authenticated")

  token_response = request(run, "POST", "/shell/tokens", token: shell_token)
  browser_token = JSON.parse(token_response.body).fetch("token")
  open_path = "/open?token=#{browser_token}&next=/settings/plugins"
  opened = request(run, "GET", open_path)
  cookie = opened["set-cookie"]&.split(";")&.first
  assert(opened.code == "302" && opened["location"]&.end_with?("/settings/plugins") && cookie, "browser handoff creates the session")
  assert(request(run, "GET", open_path).code == "401", "browser token replay is rejected")

  page = request(run, "GET", "/settings/plugins", cookie: cookie)
  assert(page.code == "200" && page.body.include?("Plugins"), "authenticated dashboard settings render")
  assert(request(run, "GET", "/").code == "302", "unauthenticated LiveView redirects")

  args = IO.popen(["/bin/ps", "-o", "command=", "-p", run[:pid].to_s], &:read)
  assert(!args.include?(run[:bootstrap]), "bootstrap token is absent from argv")

  assert(request(run, "POST", "/shell/shutdown", token: shell_token).code == "200", "graceful shutdown is accepted")
  assert(wait_exit(run).success?, "graceful shutdown exits successfully")
  sleep 0.2
  assert(!group_alive?(run[:pid]), "graceful shutdown leaves no descendants")

  remaining_output = run[:output].read
  assert(!remaining_output.include?(run[:bootstrap]), "bootstrap token is absent from runtime output")
ensure
  cleanup(run)
end

run = spawn_release
begin
  wait_ready(run)
  Process.kill("KILL", run[:pid])
  status = wait_exit(run)
  assert(status.signaled? && status.termsig == 9, "post-readiness crash is observed")
  sleep 0.2
  assert(!group_alive?(run[:pid]), "post-readiness crash leaves no descendants")
ensure
  cleanup(run)
end

run = spawn_pre_ready_failure
begin
  status = wait_exit(run)
  output = run[:output].read
  assert(!status.success? && !output.include?("READY "), "pre-readiness failure emits no false READY")
  sleep 0.2
  assert(!group_alive?(run[:pid]), "pre-readiness failure leaves no descendants")
ensure
  cleanup(run)
end
