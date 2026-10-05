# Building k with Spinel

[Spinel](https://github.com/matz/spinel) compiles Ruby ahead of time into a native executable. Built this way `k` is a single ~2.5 MB binary depending on nothing but libc, starting in a few milliseconds instead of loading a Ruby interpreter.

The `k` script stays the source of truth and keeps running on CRuby as before. `bin/k.rb` is a symlink to it, and `packages/` provides what k uses that Spinel lacks: YAML, DidYouMean, OpenSSL's SHA-256 digests without linking libssl, and SIGINT raising `Interrupt`.

## Building

Spinel is built from source. This was tested with Spinel master at `b726ae014` (2026-10-05), the `2026.09.12` release is too old.

```sh
git clone https://github.com/matz/spinel && cd spinel
git checkout b726ae0142852d34852d71021bea4971ede27190
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

- An exception nothing rescues is reported without its backtrace

## Writing Spinel compatible k code

Spinel compiles a subset of Ruby, resolving every method call at compile time. In practice for k:

- Branch on `RUBY_ENGINE == "spinel"` for code which can only work on one of the engines, Spinel discards the branch it rules out before compiling
- No method reflection such as `private_methods`, so new commands must be added to the `COMMANDS` table
- No `IO.popen` (use `Open3`), `Shellwords` (use `shell_escape`), `Time.parse` or `date`
- A bare `readline` fails to compile in k, use `$stdin.readline`
- Pass a block rather than a method object, eg. `transform_values { |value| Base64.strict_decode64(value) }` rather than `transform_values(&Base64.method(:strict_decode64))`
- String literals are frozen, as with `# frozen_string_literal: true`, so build a string you append to with `+""` or interpolation
- A socket's `recv` raises `Errno::EBADF` rather than `IOError` when another thread closes the socket, use `readpartial`
- `require "openssl"` links libssl, which a self contained binary can't depend on. OpenSSL's digests come from `packages/openssl_crypto`, so k requires OpenSSL itself on CRuby only
- `__FILE__` and `__dir__` name the source file at compile time, so don't use them to locate k or files beside it. Run another k command in process with `invoke_command` rather than running k again
- Beware that some unsupported constructs compile into code raising `NoMethodError` at runtime rather than failing the build, so exercise changed commands with the compiled binary
