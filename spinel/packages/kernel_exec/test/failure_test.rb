require "kernel_exec"

def try(label)
  yield
rescue SystemCallError => e
  puts "#{label}: #{e.class}: #{e.message} (errno #{e.errno})"
end

try("missing command") { exec "no-such-command-k-test --flag" }
try("missing program") { exec("no-such-command-k-test", "arg") }
try("not executable") { exec "/etc/hosts" }
try("directory") { exec "/tmp" }
begin
  exec
rescue ArgumentError => e
  puts "no arguments: #{e.message}"
end
