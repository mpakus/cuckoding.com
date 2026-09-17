require "socket"

host = ENV.fetch("HOST")
port = Integer(ENV.fetch("PORT"))
abort "CUCKODING_PORT mismatch" unless ENV.fetch("CUCKODING_PORT") == port.to_s

server = TCPServer.new(host, port)
trap("INT") { exit }
trap("TERM") { exit }

loop do
  socket = server.accept
  request = socket.gets.to_s
  status = request.start_with?("GET /health ") ? "200 OK" : "404 Not Found"
  body = status.start_with?("200") ? "healthy" : "missing"
  socket.write("HTTP/1.1 #{status}\r\nContent-Length: #{body.bytesize}\r\nConnection: close\r\n\r\n#{body}")
  socket.close
end
