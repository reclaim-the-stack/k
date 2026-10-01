require "kernel_spawn"

def run
  # A command line, with options passed on to Process.spawn
  pid = spawn("printf 'from the child\n'; printf 'to stderr\n' >&2; exit 4", err: File::NULL)
  waiter = Process.detach(pid)
  status = waiter.value
  puts "exit status #{status.exitstatus}, waiter alive: #{waiter.alive?}"

  # A detached process can be killed
  pid = spawn("sleep 30")
  waiter = Process.detach(pid)
  Process.kill("TERM", pid)
  puts "killed by signal #{waiter.value.termsig}"
end

run
