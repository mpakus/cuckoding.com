# frozen_string_literal: true

# A stdlib-only pipe multiplexer for the Erlang port's packet-4 transport.
# The launched runtime receives ordinary stdio, never this private framing.
STDERR.reopen(File::NULL)
STDOUT.binmode
STDOUT.sync = true
STDIN.binmode

begin
  sleep 0.05 # Let the host record this process group's start identity first.
  input_read, input_write = IO.pipe
  output_read, output_write = IO.pipe
  error_read, error_write = IO.pipe
  child = Process.spawn(*ARGV, in: input_read, out: output_write, err: error_write,
                        close_others: true)
  [input_read, output_write, error_write].each(&:close)
  lock = Mutex.new

  readers = [[output_read, 1], [error_read, 2]].map do |pipe, channel|
    Thread.new do
      loop do
        data = pipe.readpartial(16_384)
        packet = channel.chr + data
        lock.synchronize { STDOUT.write([packet.bytesize].pack('N') + packet) }
      end
    rescue EOFError, IOError, Errno::EPIPE
      nil
    ensure
      pipe.close unless pipe.closed?
    end
  end

  Thread.new do
    loop do
      header = STDIN.read(4)
      break unless header && header.bytesize == 4

      size = header.unpack1('N')
      break unless size.between?(1, 1_048_578)

      packet = STDIN.read(size)
      break unless packet && packet.bytesize == size && packet.getbyte(0) == 1

      input_write.write(packet.byteslice(1, size - 1))
      input_write.flush
    end
  rescue IOError, Errno::EPIPE
    nil
  ensure
    input_write.close unless input_write.closed?
  end

  _, status = Process.wait2(child)
  # A surviving child holding a pipe open must not hide the root's exit.
  readers.each { |reader| reader.join(0.1) }
  exit(status.exitstatus || 128 + status.termsig)
rescue StandardError
  # The host records the exit; exception text could contain private arguments.
  exit 70
end
