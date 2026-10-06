# Shellwords for Spinel, vendored from the shellwords gem, see README.md.

unless RUBY_ENGINE == "spinel"
  # This package's directory shadows CRuby's shellwords when spin test compares the tests against CRuby.
  # Load the real one in that case.
  require File.join(RbConfig::CONFIG["rubylibdir"], "shellwords")
  return
end

require_relative "vendor/shellwords/shellwords"
