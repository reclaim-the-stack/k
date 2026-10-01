# kernel_dir for Spinel

`Kernel#__dir__` for [Spinel](https://github.com/matz/spinel) compiled programs. Spinel answers `__dir__` with the directory of the source file at compile time, which means nothing once the executable has been moved or installed. Like CRuby's `__dir__` for a script, this answers the program's canonical directory: the running executable's directory, with symlinks resolved. That lets a program find files installed beside it, and invoke itself.

The executable's path comes from the OS (`_NSGetExecutablePath` on macOS, `/proc/self/exe` on Linux), and elsewhere from resolving `$PROGRAM_NAME` against `PATH` like a shell would.

`__FILE__` can't be shimmed the same way, being a keyword rather than a method.

`__dir__` is defined as a top-level method rather than by reopening `Kernel`, as in the kernel_exec package. Under CRuby, `require "kernel_dir"` leaves CRuby's own `__dir__` in place.

## Testing

```sh
spin test
```
