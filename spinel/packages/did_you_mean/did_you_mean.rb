# DidYouMean::SpellChecker for Spinel, vendored from the did_you_mean gem, see README.md.

unless RUBY_ENGINE == "spinel"
  # CRuby loads the real did_you_mean at boot, unless this package's directory shadows it as when
  # spin test compares the tests against CRuby. Load the real spell checker in that case.
  # Called indirectly since Spinel resolves literal requires at compile time, before discarding this branch.
  Kernel.send(:require, "did_you_mean/spell_checker")
  return
end

require_relative "vendor/did_you_mean/spell_checker"
