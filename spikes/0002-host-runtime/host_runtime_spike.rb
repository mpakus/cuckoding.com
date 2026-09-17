#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "open3"
require "time"

class HostRuntimeSpike
  MAX_EVENT_BYTES = 1_048_576
  SAFE_PATH = "/usr/bin:/bin:/usr/sbin:/sbin"

  def initialize(root, agent_bin)
    @root = File.expand_path(root)
    @agent_bin = File.realpath(agent_bin)
    abort "root must be an empty /private/tmp/cuckoding-0002-* directory" unless
      @root.start_with?("/private/tmp/cuckoding-0002-") && Dir.exist?(@root) && Dir.empty?(@root)

    @source = File.join(@root, "source")
    @run = File.join(@root, "run")
    @worktree = File.join(@run, "worktree")
    @agent = File.join(@run, "agent")
    @claude_config = File.join(@agent, "claude")
    @artifacts = File.join(@run, "artifacts")
    @home = ENV.fetch("HOME")
  end

  def run
    prepare
    before = cursor_state

    benign = spawn_agent(
      "benign",
      <<~PROMPT.strip
        Modify only README.md. Use the file editing tool, not a shell command, to append
        exactly `agent-change: complete` as a new line. Then use git to inspect the diff,
        then run exactly `rtk git diff -- README.md`, `rtk git add README.md`, and
        `rtk git commit -m 'feat: apply agent spike change'`. Do not create or change
        any other file. Finish with a short public summary.
      PROMPT
    )
    assert_success!(benign, "benign run")
    validate_commit

    resumed = spawn_agent(
      "resume",
      "Without using tools or editing files, reply exactly RESUME_OK if you remember appending agent-change: complete.",
      resume: benign.fetch("session_id")
    )
    assert_success!(resumed, "resume run")
    abort "native resume did not retain context" unless resumed.fetch("result", "").include?("RESUME_OK")

    canceled = spawn_agent(
      "cancel",
      "Use the shell tool to run exactly `rtk proxy sleep 60`. After it finishes, reply CANCELED_TOO_LATE.",
      cancel: true
    )
    abort "cancellation probe never started the descendant" unless canceled["descendant_sleep_seen"]
    abort "cancellation probe completed normally" if canceled["result"].to_s.include?("CANCELED_TOO_LATE")
    abort "cancellation left descendants: #{canceled.fetch("orphaned_descendant_pids")}" unless canceled.fetch("orphaned_descendant_pids").empty?
    abort "cancellation left descendant groups: #{canceled.fetch("orphaned_descendant_pgids")}" unless canceled.fetch("orphaned_descendant_pgids").empty?
    abort "cancellation left a process in group #{canceled.fetch("pgid")}" unless group_processes(canceled.fetch("pgid")).empty?

    after = cursor_state
    report = summary(benign, resumed, canceled, before, after)
    write_json(File.join(@artifacts, "home_state.json"), {"before" => before, "after" => after})
    write_json(File.join(@artifacts, "summary.json"), report)
    puts JSON.pretty_generate(report)
  end

  private

  def prepare
    FileUtils.mkdir_p([@source, @agent, @claude_config, @artifacts])
    git!("init", "-b", "main", @source, chdir: @root)
    git!("config", "user.name", "Cuckoding Spike", chdir: @source)
    git!("config", "user.email", "spike@localhost", chdir: @source)
    File.write(File.join(@source, "README.md"), "# Disposable Runtime Spike\n")
    FileUtils.mkdir_p(File.join(@source, ".cursor"))
    write_json(File.join(@source, ".cursor", "cli.json"), grant)
    write_json(File.join(@source, ".cursor", "sandbox.json"), sandbox)
    write_json(
      File.join(@agent, "cli-config.json"),
      {"version" => 1, "editor" => {"vimMode" => false}}.merge(grant)
    )
    write_json(File.join(@agent, "mcp.json"), {"mcpServers" => {}})
    git!("add", "README.md", ".cursor/cli.json", ".cursor/sandbox.json", chdir: @source)
    git!("commit", "-m", "chore: seed disposable repository", chdir: @source)
    FileUtils.mkdir_p(@run)
    git!("worktree", "add", "-b", "feature/agent-edit", @worktree, "HEAD", chdir: @source)
    write_json(
      File.join(@run, "run.json"),
      {
        "project_id" => "spike-project",
        "board_id" => "spike-board",
        "task_id" => "0002",
        "run_id" => "spike-run",
        "worktree" => @worktree,
        "grant_sha256" => Digest::SHA256.hexdigest(JSON.generate(grant)),
        "sandbox_sha256" => Digest::SHA256.hexdigest(JSON.generate(sandbox)),
        "config_dir" => @agent
      }
    )
  end

  def grant
    {
      "permissions" => {
        "allow" => ["Read(README.md)", "Write(README.md)", "Shell(rtk)", "Shell(git)", "Shell(sleep)"],
        "deny" => [
          "Read(.env*)", "Read(**/.env*)", "Write(.cursor/**)", "Write(**/*.key)",
          "Write(**/.env*)", "WebFetch(*)", "Mcp(*:*)", "Shell(rm)", "Shell(curl)",
          "Shell(wget)", "Shell(ssh)", "Shell(scp)", "Shell(gh)"
        ]
      }
    }
  end

  def sandbox
    {
      "type" => "workspace_readwrite",
      "networkPolicy" => {"default" => "deny", "allow" => []},
      "additionalReadwritePaths" => [],
      "additionalReadonlyPaths" => [],
      "disableTmpWrite" => false,
      "enableSharedBuildCache" => false
    }
  end

  def spawn_agent(label, prompt, resume: nil, cancel: false)
    args = [
      @agent_bin,
      "--print",
      "--output-format", "stream-json",
      "--sandbox", "enabled",
      "--trust",
      "--workspace", @worktree
    ]
    args.concat(["--resume", resume]) if resume
    args << prompt

    out_read, out_write = IO.pipe
    err_read, err_write = IO.pipe
    started_at = Time.now.utc
    pid = Process.spawn(child_env, *args, chdir: @worktree, out: out_write, err: err_write,
      pgroup: true, unsetenv_others: true)
    out_write.close
    err_write.close
    pgid = Process.getpgid(pid)
    start_identity = process_start_identity(pid)
    lifecycle(label, "started", pid: pid, pgid: pgid, start_identity: start_identity)

    parsed = []
    output_thread = Thread.new do
      bytes = 0
      File.open(File.join(@artifacts, "#{label}.fixture.jsonl"), "w") do |file|
        out_read.each_line do |line|
          event = JSON.parse(line)
          parsed << event
          safe = sanitize(event, resume)
          next unless safe

          encoded = JSON.generate(safe) << "\n"
          next if bytes + encoded.bytesize > MAX_EVENT_BYTES

          file.write(encoded)
          bytes += encoded.bytesize
        rescue JSON::ParserError
          lifecycle(label, "malformed_output")
        end
      end
    end
    error_thread = Thread.new do
      text = err_read.read(MAX_EVENT_BYTES).to_s
      File.write(File.join(@artifacts, "#{label}.stderr.txt"), redact(text, resume)) unless text.empty?
    end

    sleep_seen = false
    observed_descendants = []
    if cancel
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 120
      until Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
        observed_descendants = descendant_processes(pid)
        sleep_seen = observed_descendants.any? { |row| row.fetch("command").include?("sleep 60") }
        break if sleep_seen || !process_alive?(pid)
        sleep 0.25
      end
      lifecycle(
        label,
        "cancellation_requested",
        descendant_sleep_seen: sleep_seen,
        descendant_pids: observed_descendants.map { |row| row.fetch("pid") },
        descendant_pgids: observed_descendants.map { |row| row.fetch("pgid") }.uniq
      )
      status = terminate_tree(pid, pgid, observed_descendants, label)
    else
      _, status = Process.wait2(pid)
    end

    output_thread.join
    error_thread.join
    init = parsed.find { |event| event["type"] == "system" && event["subtype"] == "init" } || {}
    result = parsed.reverse.find { |event| event["type"] == "result" } || {}
    record = {
      "pid" => pid,
      "pgid" => pgid,
      "start_identity" => start_identity,
      "session_id" => init["session_id"] || result["session_id"] || resume,
      "requested_model" => "default",
      "actual_model" => init["model"],
      "permission_mode" => init["permissionMode"],
      "exit_status" => status&.exitstatus,
      "termsig" => status&.termsig,
      "signaled" => status&.signaled? || false,
      "result" => result["result"],
      "usage" => result["usage"],
      "duration_ms" => result["duration_ms"],
      "observed_sandbox_policies" => sandbox_policies(parsed),
      "started_at" => started_at.iso8601(6),
      "finished_at" => Time.now.utc.iso8601(6),
      "descendant_sleep_seen" => sleep_seen,
      "observed_descendants" => observed_descendants,
      "external_mcp_loaded" => observed_descendants.any? { |row| row.fetch("command").include?("mcp-server") },
      "orphaned_descendant_pids" => observed_descendants.filter_map do |row|
        row.fetch("pid") if process_alive?(row.fetch("pid"))
      end,
      "orphaned_descendant_pgids" => observed_descendants.map { |row| row.fetch("pgid") }.uniq.select do |child_pgid|
        !group_processes(child_pgid).empty?
      end
    }
    lifecycle(label, "finished", exit_status: record["exit_status"], termsig: record["termsig"])
    record
  ensure
    out_read&.close unless out_read&.closed?
    err_read&.close unless err_read&.closed?
  end

  def terminate_tree(pid, pgid, descendants, label)
    groups = (descendants.map { |row| row.fetch("pgid") } + [pgid]).uniq.reverse
    status = nil
    [["INT", 2], ["TERM", 2], ["KILL", 1]].each do |signal, wait_seconds|
      groups.each do |group|
        Process.kill(signal, -group)
        lifecycle(label, "signal_sent", signal: signal, pgid: group)
      rescue Errno::ESRCH
        nil
      end

      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + wait_seconds
      until Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
        waited = Process.waitpid2(pid, Process::WNOHANG) unless status
        status = waited.last if waited
        groups_alive = groups.any? { |group| !group_processes(group).empty? }
        break if status && !groups_alive
        sleep 0.05
      end
      break if groups.all? { |group| group_processes(group).empty? }
    end
    status || Process.wait2(pid).last
  rescue Errno::ECHILD
    status
  end

  def validate_commit
    changed = git!("diff", "HEAD^", "HEAD", "--name-only", chdir: @worktree).lines.map(&:strip).reject(&:empty?)
    abort "agent changed unexpected files: #{changed.inspect}" unless changed == ["README.md"]
    abort "agent did not write expected content" unless File.read(File.join(@worktree, "README.md")).lines.last&.strip == "agent-change: complete"
    abort "agent left worktree dirty" unless git!("status", "--porcelain", chdir: @worktree).empty?
    abort "agent changed source checkout" unless git!("status", "--porcelain", chdir: @source).empty?
  end

  def summary(benign, resumed, canceled, before, after)
    changed_global = after.select { |path, metadata| before[path] != metadata }
    {
      "runtime" => "Cursor Agent",
      "version" => command!([@agent_bin, "--version"], chdir: @worktree).strip,
      "architecture" => command!(["/usr/bin/uname", "-m"], chdir: @worktree).strip,
      "worktree_gitdir_valid" => File.file?(File.join(@worktree, ".git")),
      "session_id_matches" => benign["session_id"] == resumed["session_id"],
      "benign" => benign,
      "resume" => resumed,
      "cancel" => canceled,
      "source_checkout_clean" => git!("status", "--porcelain", chdir: @source).empty?,
      "worktree_clean" => git!("status", "--porcelain", chdir: @worktree).empty?,
      "worktree_commit" => git!("rev-parse", "HEAD", chdir: @worktree).strip,
      "global_cursor_files_created_or_changed" => changed_global,
      "production_eligible" => !canceled.fetch("external_mcp_loaded"),
      "unsupported_assumptions" => canceled.fetch("external_mcp_loaded") ? [
        "Cursor Agent discovers and starts a user-global Claude-compatible MCP plugin despite isolated config directories and an MCP deny rule."
      ] : [],
      "effective_grant" => grant.merge(
        "cwd" => "<RUN_ROOT>/run/worktree",
        "sandbox" => sandbox,
        "environment_keys" => child_env.keys.sort
      )
    }
  end

  def cursor_state
    cursor_root = File.join(@home, ".cursor")
    paths = Dir.glob(File.join(cursor_root, "{projects,plans,acp-sessions}", "**", "*"), File::FNM_DOTMATCH)
    paths.select { |path| File.file?(path) }.to_h do |path|
      [path.sub(cursor_root + "/", "<HOME>/.cursor/"), file_metadata(path)]
    end
  end

  def file_metadata(path)
    stat = File.stat(path)
    {"size" => stat.size, "mtime" => stat.mtime.utc.iso8601(6)}
  end

  def child_env
    env = {
      "PATH" => "#{File.dirname(@agent_bin)}:#{SAFE_PATH}",
      "HOME" => @home,
      "CURSOR_CONFIG_DIR" => @agent,
      "CLAUDE_CONFIG_DIR" => @claude_config
    }
    %w[LANG LC_ALL TZ].each { |key| env[key] = ENV[key] if ENV[key] }
    env
  end

  def git!(*args, chdir:)
    command!(["/usr/bin/git", *args], chdir: chdir)
  end

  def command!(args, chdir:)
    stdout, stderr, status = Open3.capture3(child_env, *args, chdir: chdir, unsetenv_others: true)
    abort "command failed (#{args.first}): #{stderr}" unless status.success?
    stdout
  end

  def process_start_identity(pid)
    stdout, status = Open3.capture2("/bin/ps", "-p", pid.to_s, "-o", "lstart=")
    status.success? ? stdout.strip : nil
  end

  def process_alive?(pid)
    Process.kill(0, pid)
    true
  rescue Errno::ESRCH
    false
  end

  def group_processes(pgid)
    process_rows.select { |row| row.fetch("pgid") == pgid }
  end

  def descendant_processes(root_pid)
    rows = process_rows
    parent_ids = [root_pid]
    descendants = []
    loop do
      children = rows.select { |row| parent_ids.include?(row.fetch("ppid")) && !descendants.include?(row) }
      break if children.empty?

      descendants.concat(children)
      parent_ids = children.map { |row| row.fetch("pid") }
    end
    descendants
  end

  def process_rows
    stdout, = Open3.capture2("/bin/ps", "-axo", "pid=,ppid=,pgid=,command=")
    stdout.lines.map do |line|
      pid, ppid, group, command = line.strip.split(/\s+/, 4)
      {"pid" => pid.to_i, "ppid" => ppid.to_i, "pgid" => group.to_i, "command" => redact(command.to_s, nil)}
    end
  end

  def sandbox_policies(events)
    events.filter_map do |event|
      event.dig("tool_call", "shellToolCall", "args", "requestedSandboxPolicy")
    end.uniq
  end

  def lifecycle(label, event, fields = {})
    File.open(File.join(@artifacts, "lifecycle.jsonl"), "a") do |file|
      file.puts(JSON.generate({"at" => Time.now.utc.iso8601(6), "run" => label, "event" => event}.merge(fields)))
    end
  end

  def assert_success!(record, label)
    return if record["exit_status"] == 0

    abort "#{label} failed: exit=#{record["exit_status"]} signal=#{record["termsig"]}"
  end

  def sanitize(value, session_id)
    case value
    when Hash
      return nil if value["type"].to_s.match?(/thinking|reasoning|analysis/i)

      value.each_with_object({}) do |(key, child), clean|
        next if key.to_s.match?(/thinking|reasoning|analysis|signature/i)
        sanitized = sanitize(child, session_id)
        clean[key] = sanitized unless sanitized.nil?
      end
    when Array
      value.filter_map { |child| sanitize(child, session_id) }
    when String
      redact(value, session_id)
    else
      value
    end
  end

  def redact(text, session_id)
    value = text.to_s.gsub(@root, "<RUN_ROOT>").gsub(@home, "<HOME>")
    value = value.gsub(session_id, "<SESSION_ID>") if session_id
    value.gsub(/[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}/i, "<UUID>")
  end

  def write_json(path, value)
    File.write(path, JSON.pretty_generate(value) << "\n")
  end
end

abort "usage: #{$PROGRAM_NAME} ROOT CURSOR_AGENT_BIN" unless ARGV.length == 2
HostRuntimeSpike.new(ARGV.fetch(0), ARGV.fetch(1)).run
