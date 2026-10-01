# kernel_exec for Spinel

`Kernel#exec` for [Spinel](https://github.com/matz/spinel), which refuses to compile `exec` since it has no process replacing implementation of its own. The process is replaced through `execvp(3)`, behaving as CRuby's `exec`:

- `exec(command)` runs the command through `/bin/sh -c` when it contains shell meta characters, starts with a shell reserved word or special built-in, or assigns a variable, and otherwise splits it on whitespace and runs the program directly (CRuby's `rb_exec_fillarg` rules)
- `exec(program, *args)` runs the program directly with the arguments as given
- A failed exec raises the `Errno` exception CRuby raises, with the same message
- Output still buffered in `$stdout` isn't flushed, as in CRuby, so it's lost when `$stdout` isn't a TTY

Not supported: the environment Hash and options forms, and `exec` with an explicit receiver (`Kernel.exec`). `exec` is defined as a top-level method rather than by reopening `Kernel`, since Spinel doesn't recognize a `Kernel` reopening as defining `exec` when the require is inside a conditional.

Under CRuby, `require "kernel_exec"` leaves CRuby's own `exec` in place, which makes `spin test` compare this implementation against it.

## Testing

```sh
spin test
```
