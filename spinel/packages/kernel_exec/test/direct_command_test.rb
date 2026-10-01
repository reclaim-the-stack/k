require "kernel_exec"

# No meta characters: split on whitespace and run directly
exec "printf %s, one  two\tthree"
