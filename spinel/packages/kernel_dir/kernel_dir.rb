# Kernel#__dir__ for Spinel, answering the directory of the running executable, see README.md.

unless RUBY_ENGINE == "spinel"
  return # CRuby's own __dir__
end

module KernelDir
  native_lib "kernel_dir"
  # C entry points avoid the sp_ prefix, which Spinel uses for a program's own top-level methods
  native_func :os_executable_path, [], :string, "spinel_kernel_dir_executable_path"

  # The canonical path of the running executable. Where the OS can't tell (neither macOS nor Linux),
  # resolve $PROGRAM_NAME the way a shell would.
  def self.executable_path
    path = KernelDir.os_executable_path
    return path unless path.empty?

    program = $PROGRAM_NAME
    unless program.include?("/")
      program = ENV.fetch("PATH", "").split(":")
        .map { |dir| File.join(dir, program) }
        .find { |candidate| File.executable?(candidate) } || program
    end
    File.realpath(program)
  end
end

# Like CRuby's __dir__ for a script, the canonical directory of the program: the executable's
# directory with symlinks resolved, since a compiled program has no source file at run time.
# Defined at the top level for the same reason as kernel_exec's exec.
def __dir__
  File.dirname(KernelDir.executable_path)
end
