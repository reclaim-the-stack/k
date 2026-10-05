# did_you_mean for Spinel

`DidYouMean::SpellChecker` for [Spinel](https://github.com/matz/spinel). CRuby preloads the did_you_mean gem at boot, while Spinel ships no did_you_mean at all. Only the spell checker is provided, not the "Did you mean?" suggestions DidYouMean adds to `NameError` messages.

`vendor/did_you_mean` holds `spell_checker.rb`, `levenshtein.rb` and `jaro_winkler.rb` from did_you_mean 2.0.0 (MIT, see `vendor/did_you_mean/LICENSE.txt`), the version CRuby 4.0 ships. The only change from upstream replaces `str1.each_codepoint.with_index(1)` with the equivalent `str1.codepoints.each.with_index(1)`, since Spinel's `each_codepoint` without a block returns an Array rather than an Enumerator.

## Testing

```sh
spin test # compared against CRuby's own DidYouMean::SpellChecker
```
