#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "json"
require "net/http"
require "open3"
require "securerandom"
require "socket"
require "tmpdir"
require "time"

ROOT = File.expand_path(__dir__)
RELEASE = ENV.fetch("CUCKODING_RELEASE_PATH", File.join(ROOT, "release/bin/cuckoding"))
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

def temporary_directory(prefix)
  Dir.mktmpdir(prefix).sub(%r{\A/var/}, "/private/var/")
end

def release_env(directory, token_path, port, safe_mode: false)
  environment = {
    "PATH" => SAFE_PATH,
    "HOME" => directory,
    "LANG" => "en_US.UTF-8",
    "PHX_SERVER" => "true",
    "RELEASE_DISTRIBUTION" => "none",
    "CUCKODING_PORT" => port.to_s,
    "CUCKODING_DATABASE_PATH" => File.join(directory, "cuckoding.sqlite3"),
    "CUCKODING_BOOTSTRAP_FILE" => token_path
  }
  environment["CUCKODING_SAFE_MODE"] = "true" if safe_mode
  environment
end

def spawn_release(safe_mode: false)
  directory = temporary_directory("cuckoding-shell-")
  token_path = File.join(directory, "bootstrap")
  bootstrap = SecureRandom.hex(32)
  File.write(token_path, "#{SecureRandom.hex(64)}\n#{bootstrap}", mode: "w", perm: 0o600)
  port = free_port
  env = release_env(directory, token_path, port, safe_mode: safe_mode)

  migration_log = File.join(directory, "migration.log")
  migration_status = File.open(migration_log, "w", 0o600) do |output|
    migrated = Process.spawn(
      env,
      RELEASE,
      "eval",
      "Cuckoding.Release.migrate()",
      out: output,
      err: [:child, :out],
      unsetenv_others: true
    )
    Process.waitpid2(migrated).last
  end
  unless migration_status.success?
    raise "release migration failed (#{migration_status.inspect}): #{File.read(migration_log)}"
  end

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
  directory = temporary_directory("cuckoding-shell-failure-")
  token_path = File.join(directory, "bootstrap")
  bootstrap = SecureRandom.hex(32)
  File.write(token_path, "#{SecureRandom.hex(64)}\n#{bootstrap}", mode: "w", perm: 0o600)
  reader, writer = IO.pipe
  port = free_port
  env = release_env(directory, token_path, port)
  env.delete("CUCKODING_DATABASE_PATH")
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
  output = []

  while (remaining = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)).positive?
    next unless IO.select([run[:output]], nil, nil, remaining)

    line = run[:output].gets
    break unless line
    output << line
    output.shift while output.length > 40
    next unless line.start_with?("READY ")

    payload = JSON.parse(line.delete_prefix("READY "))
    expected = {"port" => run[:port], "version" => "0.1.0"}
    raise "READY payload mismatch: #{payload.inspect}" unless payload == expected

    run[:ready_seconds] = Process.clock_gettime(Process::CLOCK_MONOTONIC) - run[:started_at]
    return payload
  end

  raise "release did not emit exact READY payload:\n#{output.join}"
end

def request(run, method, path, token: nil, cookie: nil, host: nil, json: nil)
  http = Net::HTTP.new("127.0.0.1", run[:port])
  request = Net::HTTPGenericRequest.new(method, false, true, path)
  request["Authorization"] = "Bearer #{token}" if token
  request["Cookie"] = cookie if cookie
  request["Host"] = host if host
  if json
    request["Content-Type"] = "application/json"
    request.body = JSON.generate(json)
  end
  http.request(request)
end

def release_eval(run, expression)
  token_path = File.join(run[:directory], "eval-bootstrap")
  File.write(token_path, "#{SecureRandom.hex(64)}\n#{SecureRandom.hex(32)}", mode: "w", perm: 0o600)
  log = File.join(run[:directory], "eval.log")
  status = File.open(log, "a", 0o600) do |output|
    pid = Process.spawn(
      release_env(run[:directory], token_path, free_port, safe_mode: true),
      RELEASE,
      "eval",
      expression,
      out: output,
      err: [:child, :out],
      unsetenv_others: true
    )
    Process.waitpid2(pid).last
  end
  FileUtils.rm_f(token_path)
  [status, File.read(log)]
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
  exited = Process.waitpid2(run[:pid], Process::WNOHANG)
  unless exited
    Process.kill("KILL", -run[:pid]) if group_alive?(run[:pid])
    Process.waitpid(run[:pid])
  end
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
  assert(
    status.code == "200" &&
      JSON.parse(status.body) == {
        "active_runs" => 0,
        "attention" => 0,
        "safe_mode" => false,
        "runtime_workers" => true
      },
    "shell status is authenticated"
  )

  diagnostics = request(run, "POST", "/shell/diagnostics", token: shell_token)
  diagnostics_body = JSON.parse(diagnostics.body)
  diagnostics_path = diagnostics_body.fetch("path")
  expected_entries = %w[
    manifest.json configuration.json migrations.json plugins.json
    power-events.json recent-errors.json processes.json
  ]
  listed, list_error, list_status = Open3.capture3("/usr/bin/unzip", "-Z1", diagnostics_path)
  assert(
    diagnostics.code == "200" && list_status.success? && listed.lines.map(&:strip) == expected_entries,
    "diagnostics archive exposes only the reviewed file set: #{list_error}"
  )
  extracted, extract_error, extract_status = Open3.capture3("/usr/bin/unzip", "-p", diagnostics_path)
  assert(
    extract_status.success? && !extracted.include?(run[:bootstrap]) && !extracted.include?(shell_token),
    "diagnostics archive excludes launch credentials: #{extract_error}"
  )
  assert(File.stat(diagnostics_path).mode & 0o077 == 0, "diagnostics archive is owner-only")

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

  audit, audit_error, audit_status = Open3.capture3(
    "/usr/bin/sqlite3",
    File.join(run[:directory], "cuckoding.sqlite3"),
    "SELECT event_type, method, path, status FROM security_audit_events ORDER BY rowid"
  )
  audit_rows = audit.lines.map(&:strip)
  assert(
    audit_status.success? && audit_rows.length == 6 &&
      audit_rows.include?("auth.browser_token_rejected|GET|/open|401") &&
      audit_rows.include?("auth.loopback_boundary_rejected|GET|/shell/status|403") &&
      !audit.include?(run[:bootstrap]) && !audit.include?(shell_token) && !audit.include?(browser_token),
    "authorization rejections are durably audited without credentials: #{audit_error}"
  )

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

run = spawn_release(safe_mode: true)
begin
  wait_ready(run)
  bootstrap_response = request(run, "POST", "/shell/bootstrap", token: run[:bootstrap])
  shell_token = JSON.parse(bootstrap_response.body).fetch("shell_token")
  status = request(run, "GET", "/shell/status", token: shell_token)
  safe_status = JSON.parse(status.body)
  assert(
    status.code == "200" && safe_status.fetch("safe_mode") && !safe_status.fetch("runtime_workers"),
    "safe mode starts without runtime workers"
  )
  assert(
    request(run, "POST", "/shell/diagnostics", token: shell_token).code == "200",
    "safe mode can export diagnostics"
  )
  assert(request(run, "POST", "/shell/shutdown", token: shell_token).code == "200", "safe mode accepts graceful shutdown")
  assert(wait_exit(run).success?, "safe mode exits successfully")
ensure
  cleanup(run)
end

run = spawn_release
begin
  wait_ready(run)
  bootstrap_response = request(run, "POST", "/shell/bootstrap", token: run[:bootstrap])
  shell_token = JSON.parse(bootstrap_response.body).fetch("shell_token")
  prepared = request(
    run,
    "POST",
    "/shell/update/prepare",
    token: shell_token,
    json: {version: "0.2.0", schema_change: true}
  )
  attempt_id = JSON.parse(prepared.body).fetch("attempt_id")
  pending_path = File.join(run[:directory], "pending-update.json")
  pending = JSON.parse(File.read(pending_path))
  assert(prepared.code == "200" && pending.fetch("attempt_id") == attempt_id, "update snapshot is durable before install")

  installing = request(
    run,
    "POST",
    "/shell/update/installing",
    token: shell_token,
    json: {attempt_id: attempt_id}
  )
  assert(installing.code == "200", "update enters installing only after snapshot")
  assert(request(run, "POST", "/shell/shutdown", token: shell_token).code == "200", "update drill stops the runtime")
  assert(wait_exit(run).success?, "update drill runtime exits cleanly")

  mutation = <<~ELIXIR.strip
    {:ok, _, _} = Ecto.Migrator.with_repo(Cuckoding.Repo, fn repo ->
      Ecto.Adapters.SQL.query!(repo, "CREATE TABLE update_drill (id INTEGER PRIMARY KEY)", [])
    end)
  ELIXIR
  mutation_status, mutation_log = release_eval(run, mutation)
  assert(mutation_status.success?, "update drill applies a schema change: #{mutation_log}")

  rollback_status, rollback_log = release_eval(run, "Cuckoding.Release.rollback_pending(\"update_drill\")")
  assert(rollback_status.success?, "failed candidate restores the compatible snapshot: #{rollback_log}")
  refute_table = <<~ELIXIR.strip
    {:ok, _, _} = Ecto.Migrator.with_repo(Cuckoding.Repo, fn repo ->
      %{rows: [[count]]} = Ecto.Adapters.SQL.query!(repo, "SELECT count(*) FROM sqlite_master WHERE type = 'table' AND name = 'update_drill'", [])
      0 = count
      "rolled_back" = Cuckoding.Repo.get!(Cuckoding.Updates.Attempt, "#{attempt_id}").state
    end)
  ELIXIR
  restored_status, restored_log = release_eval(run, refute_table)
  assert(restored_status.success?, "rollback restores schema and records the attempt: #{restored_log}")
  assert(!File.exist?(pending_path), "rollback clears the pending update marker")
  assert(File.file?(File.join(pending.fetch("backup_path"), "failed-current.sqlite3")), "rollback preserves the failed database")
ensure
  cleanup(run)
end
