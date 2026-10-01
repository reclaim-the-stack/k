require "kernel_exec"

# Shell meta characters run the command through /bin/sh, which then names itself sh
exec "echo \"replaced by $0: $((1 + 2))\""
