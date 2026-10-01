# kernel_spawn for Spinel

`Kernel#spawn` and `Process.detach` for [Spinel](https://github.com/matz/spinel), which only provides `Process.spawn`.

- `spawn(command, **options)` runs the command line as `Process.spawn` does. Spawning a program with separate arguments (`spawn(program, *args)`) raises `NotImplementedError`, since Spinel's `Process.spawn` garbles splatted arguments.
- `Process.detach(pid)` answers a thread waiting for the process, whose value is its `Process::Status`, like CRuby's. Unlike CRuby's, that thread has no `pid` method.

`spawn` is defined as a top-level method, as in the kernel_exec package. Under CRuby, `require "kernel_spawn"` leaves CRuby's own `spawn` and `Process.detach` in place, which makes `spin test` compare this implementation against them.

## Testing

```sh
spin test
```
