# Kernel#exec for Spinel, which has no process replacing exec of its own, see README.md.

unless RUBY_ENGINE == "spinel"
  return # CRuby's own Kernel#exec
end

module KernelExec
  native_lib "kernel_exec"
  # C entry points avoid the sp_ prefix, which Spinel uses for a program's own top-level methods
  native_func :execvp, [:string, :any], :int, "spinel_kernel_execvp"
  native_func :errno_name, [:int], :string, "spinel_kernel_exec_errno_name"
  native_func :strerror, [:int], :string, "spinel_kernel_exec_strerror"

  # A command string containing any of these is run by /bin/sh, as in CRuby
  SHELL_META_CHARACTERS = "*?{}[]<>()~&|\\$;'`\"\n#"
  # As are commands starting with a POSIX shell reserved word or special built-in
  POSIX_SHELL_COMMANDS = %w[
    ! . : break case continue do done elif else esac eval exec exit export fi for if in readonly return set
    shift then times trap unset until while
  ].freeze

  # The [path, argv] CRuby's exec runs a single command string as (see rb_exec_fillarg in process.c)
  def self.command_line(command)
    return ["/bin/sh", ["sh", "-c", command]] if KernelExec.shell?(command)

    argv = command.split(/[ \t]+/).reject(&:empty?)
    [argv.first.to_s, argv]
  end

  def self.shell?(command)
    return true if command.each_char.any? { |char| SHELL_META_CHARACTERS.include?(char) }

    first_word = command.split(/[ \t]+/).reject(&:empty?).first.to_s
    # An = in the first word is a variable assignment, unless a / comes first
    slash = first_word.index("/")
    equals = first_word.index("=")
    return true if equals && (slash.nil? || equals < slash)
    return false if slash

    POSIX_SHELL_COMMANDS.include?(first_word)
  end

  # Raise the Errno exception CRuby's exec would for a failed exec of `name`
  def self.raise_exec_error(error, name)
    # Spinel's Errno classes don't prefix their message with the strerror text, so do it here
    message = "#{KernelExec.strerror(error)} - #{name}"
    case KernelExec.errno_name(error)
    when "E2BIG" then raise Errno::E2BIG, message
    when "EACCES" then raise Errno::EACCES, message
    when "EFAULT" then raise Errno::EFAULT, message
    when "EINVAL" then raise Errno::EINVAL, message
    when "EIO" then raise Errno::EIO, message
    when "EISDIR" then raise Errno::EISDIR, message
    when "ELOOP" then raise Errno::ELOOP, message
    when "EMFILE" then raise Errno::EMFILE, message
    when "ENAMETOOLONG" then raise Errno::ENAMETOOLONG, message
    when "ENFILE" then raise Errno::ENFILE, message
    when "ENOENT" then raise Errno::ENOENT, message
    when "ENOEXEC" then raise Errno::ENOEXEC, message
    when "ENOMEM" then raise Errno::ENOMEM, message
    when "ENOTDIR" then raise Errno::ENOTDIR, message
    when "EPERM" then raise Errno::EPERM, message
    when "ETXTBSY" then raise Errno::ETXTBSY, message
    else raise SystemCallError, message
    end
  end
end

# Kernel#exec(command) and Kernel#exec(program, *args). The environment Hash and options forms aren't
# supported. Defined at the top level rather than in a module Kernel reopening, which Spinel doesn't
# recognize as defining exec when the require is inside a conditional (as in k's RUBY_ENGINE check).
def exec(*args)
  raise ArgumentError, "wrong number of arguments (given 0, expected 1+)" if args.empty?

  # Like CRuby, output still buffered in $stdout is lost (as when it isn't a TTY)
  path, argv = args.size == 1 ? KernelExec.command_line(args.first) : [args.first, args]
  error = KernelExec.execvp(path, argv)
  KernelExec.raise_exec_error(error, path)
end
