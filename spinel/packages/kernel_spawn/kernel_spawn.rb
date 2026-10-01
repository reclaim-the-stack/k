# Kernel#spawn and Process.detach for Spinel, which only has Process.spawn, see README.md.

unless RUBY_ENGINE == "spinel"
  return # CRuby's own spawn and Process.detach
end

# Kernel#spawn(command, **options), as Process.spawn. Defined at the top level for the same reason
# as kernel_exec's exec.
def spawn(*args, **options)
  # Spinel's Process.spawn garbles splatted arguments, so only the command line form is supported
  unless args.size == 1
    raise NotImplementedError, "kernel_spawn only supports spawn(command, **options) under Spinel"
  end

  Process.spawn(args.first, **options)
end

module Process
  # The thread waiting for the process, whose value is its Process::Status, as CRuby's Process.detach
  def self.detach(pid)
    Thread.new { Process.waitpid2(pid)[1] }
  end
end
