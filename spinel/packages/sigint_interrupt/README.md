# sigint_interrupt for Spinel

CRuby raises `Interrupt` in the main thread when the process receives SIGINT (Ctrl-C), which lets a program `rescue Interrupt` to clean up or exit gracefully. A [Spinel](https://github.com/matz/spinel) compiled program has no such default and is killed by the signal outright. Requiring this package traps SIGINT to raise `Interrupt` as CRuby does, including while blocked in `sleep` or socket IO.

An `Interrupt` nothing rescues still ends the program, with exit status 1, where CRuby re-raises the signal to exit with 130.

Under CRuby, `require "sigint_interrupt"` does nothing.

## Testing

```sh
spin test
```
