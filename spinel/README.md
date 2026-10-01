# Building k with Spinel

[Spinel](https://github.com/matz/spinel) compiles Ruby ahead of time into a native executable. Built this way `k` is a single ~2 MB binary depending on nothing but libc, starting in a few milliseconds instead of loading a Ruby interpreter.

The `k` script stays the source of truth and keeps running on CRuby as before. `bin/k.rb` is a symlink to it, and `packages/` provides what k uses that Spinel lacks: YAML, DidYouMean, `Kernel#exec`, `Kernel#spawn` and `Process.detach`, OpenSSL's SHA-256 digests, and SIGINT raising `Interrupt`.

## Building

Spinel is built from source. This was tested with Spinel master at `c66837f9a` (2026-10-01), the `2026.09.12` release is too old.

```sh
git clone https://github.com/matz/spinel && cd spinel
git checkout c66837f9a10e5b3bc85e7f480bfe32ccfb25dbec
make deps && make
sudo make install # or put the checkout's bin/ on your PATH

cd path/to/k/spinel
spin build # => build/bin/k
```

## Testing

The spec suite runs against any k executable:

```sh
K_EXECUTABLE=spinel/build/bin/k bundle exec rspec
```

## Differences from running k with Ruby

- `k applications <application>` prints an extra blank line for an application without deployments or resources, due to a Spinel bug

## Writing Spinel compatible k code

Spinel compiles a subset of Ruby, resolving every method call at compile time. In practice for k:

- Branch on `RUBY_ENGINE == "spinel"` for code which can only work on one of the engines, Spinel discards the branch it rules out before compiling
- Spinel resolves literal `require`s at compile time, even inside a discarded branch, so CRuby only libraries need `Kernel.send(:require, "name")`
- No `send` with a computed method name, new commands must be added to the `COMMANDS` table
- No `IO.popen` (use `Open3`), `Kernel#readline` (use `$stdin.readline`) or `Shellwords` (use `shell_escape`)
- `$?` is the raw wait status Integer rather than a `Process::Status`, use `last_exit_status`
- String literals are frozen, as with `# frozen_string_literal: true`, so build a string you append to with `+""` or interpolation
- An Integer local read before it's assigned is 0 rather than nil, so assign nil up front where that matters, eg. for an `ensure`
- A socket's `recv` skips data its `read` already buffered, use `readpartial` to read what's available
- `require "openssl"` links libssl, which a self contained binary can't depend on. OpenSSL's digests come from `packages/openssl_crypto`, so k requires OpenSSL itself on CRuby only
- `__FILE__` and `__dir__` name the source file at compile time, so don't use them to locate k or files beside it. Run another k command in process with `invoke_command` rather than running k again
- Beware that some unsupported constructs compile into code raising `NoMethodError` at runtime rather than failing the build, so exercise changed commands with the compiled binary
