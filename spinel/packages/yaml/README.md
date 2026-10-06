# yaml for Spinel

`YAML.load` / `YAML.dump` for [Spinel](https://github.com/matz/spinel), which ships no YAML support of its own. It binds a vendored copy of [libyaml](https://github.com/yaml/libyaml) (the same parser and emitter Psych uses) and mirrors Psych's behaviour on top of it:

- Scalar resolution as Psych's `ScalarScanner` (YAML 1.1 booleans such as `yes`/`off`, `0755` octal, `1,000`, base 60 `1:30`, `.inf`)
- Output style as Psych's `YAMLTree` (which strings get quoted and how, literal blocks for multi line strings, `&1` / `*1` anchors for repeated objects)
- Merge keys (`<<: *defaults`, including `!!merge`)
- Psych's load modes: `load` / `load_file` / `safe_load` refuse aliases unless `aliases: true`, `safe_load` refuses Symbol / Date / Time, with Psych's exception classes and messages
- `Object#to_yaml`

Under CRuby, `require "yaml"` of this package hands over to the real Psych, which makes `spin test` compare this implementation against Psych.

## Not supported yet

- Symbol, Date and Time values load as Strings in the modes that permit them (the Spinel package ABI has no way to intern symbols and there is no Date class)
- Non String hash keys are refused with `Psych::DisallowedClass` (the ABI's hash builder is String keyed)
- Binary strings (`!binary`), object tags (`!ruby/object`), `load_stream`, `permitted_classes:` and dump options like `line_width:`

## Layout

- `yaml.rb`: the Ruby API and `native_func` bindings
- `sp_yaml.c`: glue between libyaml's event API and Spinel values
- `native/libyaml_*.c`: one wrapper per libyaml source file, supplying the defines libyaml's own build would pass (spin compiles carried C with `-I <package root>` only, and libyaml's `yaml_private.h` has no include guard so the sources can't share a single translation unit)
- `vendor/libyaml`: libyaml 0.2.5 (MIT, see `vendor/libyaml/License`), limited to the files that are compiled. The only change from upstream is `src/yaml_private.h` including `"../include/yaml.h"` rather than `<yaml.h>`.

## Testing

```sh
spin test                       # each test/*.rb compared against CRuby + Psych
SPINEL_GC_STRESS=1 spin test    # the same with a collection every few KB, to catch unrooted values
```
