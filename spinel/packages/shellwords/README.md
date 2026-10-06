# shellwords for Spinel

`Shellwords` for [Spinel](https://github.com/matz/spinel), which ships no shellwords of its own: `Shellwords.escape` / `split` / `join` (and their `shell*` and `shellwords` names), plus `String#shellescape`, `String#shellsplit` and `Array#shelljoin`.

`vendor/shellwords/shellwords.rb` is `lib/shellwords.rb` from shellwords 0.2.2 (Ruby's license or BSD-2-Clause, see `vendor/shellwords/BSDL`), the version CRuby 4.0 ships, unmodified.

## Testing

```sh
spin test # compared against CRuby's own Shellwords
```
