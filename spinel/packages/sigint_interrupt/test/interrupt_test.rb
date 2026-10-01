require "sigint_interrupt"

# Rescued as Interrupt, a SignalException for SIGINT
begin
  Process.kill("INT", Process.pid)
  sleep 1
  puts "not interrupted"
rescue Interrupt => e
  puts "interrupted: #{e.class} #{Signal.signame(e.signo)} #{e.is_a?(SignalException)}"
end

# Including when it arrives while blocked in IO, with other threads around
require "socket"
server = TCPServer.new("127.0.0.1", 0)
Thread.new do
  sleep 0.2
  Process.kill("INT", Process.pid)
end
begin
  server.accept
rescue Interrupt
  puts "interrupted while accepting"
end
