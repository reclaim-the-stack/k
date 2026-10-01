# Building k with Spinel

[Spinel](https://github.com/matz/spinel) compiles Ruby ahead of time into a native executable. Built this way `k` is a single ~2 MB binary depending on nothing but libc, starting in a few milliseconds instead of loading a Ruby interpreter.

The `k` script stays the source of truth and keeps running on CRuby as before. `bin/k.rb` is a symlink to it, and `packages/` provides YAML and DidYouMean, which Spinel lacks.

## Building

Spinel is built from source. This was tested with Spinel master at `438241961` (2026-10-01), the `2026.09.12` release is too old.

```sh
git clone https://github.com/matz/spinel && cd spinel
git checkout 438241961cd7e9f0e1dc1cb81f261dd37cb9d756
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

- `k pg:proxy` still runs the Ruby `k_pg_proxy` script from the directory the k binary lives in

## Writing Spinel compatible k code

Spinel compiles a subset of Ruby, resolving every method call at compile time. In practice for k:

- Branch on `RUBY_ENGINE == "spinel"` for code which can only work on one of the engines, Spinel discards the branch it rules out before compiling
- Spinel resolves literal `require`s at compile time, even inside a discarded branch, so CRuby only libraries need `Kernel.send(:require, "name")`
- No `send` with a computed method name, new commands must be added to the `COMMANDS` table
- No `Kernel#exec` (use `exec_command`), `IO.popen` (use `Open3`), `Kernel#readline` (use `$stdin.readline`) or `Shellwords` (use `shell_escape`)
- `$?` is the raw wait status Integer rather than a `Process::Status`, use `last_exit_status`
- No `__FILE__` / `__dir__` for locating k itself, they name the source file at compile time, use `k_executable` / `k_directory`
- Beware that some unsupported constructs compile into code raising `NoMethodError` at runtime rather than failing the build, so exercise changed commands with the compiled binary
