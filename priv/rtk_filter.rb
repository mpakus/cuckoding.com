# frozen_string_literal: true

# Only redacted, bounded runner output is supplied here. Never execute the
# original command: a filter failure must not execute user work twice.
require "open3"
require "timeout"

begin
  Open3.popen2(ARGV.fetch(0), "pipe", err: File::NULL) do |input, output, child|
    begin
      filtered = Timeout.timeout(5) do
        input.write(File.binread(ARGV.fetch(1)))
        input.close
        output.read
      end
      status = child.value
      STDOUT.write(filtered) if status.success?
      exit(status.success? ? 0 : 1)
    rescue Timeout::Error
      Process.kill("KILL", child.pid) rescue nil
      child.value
      exit 1
    end
  end
rescue StandardError
  exit 1
end
