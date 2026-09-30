# yaml -- YAML.load / YAML.dump for Spinel over the vendored libyaml 0.2.5.
#
# The C in sp_yaml.c builds the loaded document as ordinary Hash / Array /
# String / Integer / Float / true / false / nil values, and walks them back out
# for a dump, mirroring Psych's scalar resolution, safe-load defaults and output
# style. See the top of sp_yaml.c for what is not covered yet.

# Under CRuby (spin test's oracle, or a program run with plain `ruby`) this file
# shadows the stdlib's yaml.rb, so hand over to the real Psych. Spinel drops the
# branch before analysis.
unless RUBY_ENGINE == "spinel"
  Kernel.send(:require, "psych")   # not a literal `require`: spinel splices those at parse time, before this branch is pruned
  YAML = Psych
  return
end

module Psych
  class Exception < ::RuntimeError; end
  class SyntaxError < Exception; end
  class BadAlias < Exception; end
  class AliasesNotEnabled < BadAlias; end
  class AnchorNotDefined < BadAlias; end
  class DisallowedClass < Exception; end
end

module YAML
  native_lib "yaml"
  # C entry points avoid the sp_ prefix: spinel names a top-level Ruby method
  # `foo` sp_foo, so sp_yaml_load would collide with a program's own `def yaml_load`.
  native_func :parse_with, [:string, :int, :string], :any, "spinel_yaml_load"
  native_func :dump, [:any], :string, "spinel_yaml_dump"

  # Load modes, as sp_yaml.c's YL_* flags.
  ALIASES = 1
  PERMIT_SYMBOL = 4
  NIL_FALLBACK = 8

  # native_func methods need an explicit receiver, even inside this module.
  def self.unsafe_load(yaml, filename: "") = YAML.parse_with(yaml, ALIASES, filename)
  def self.load(yaml, aliases: false, filename: "") = YAML.parse_with(yaml, NIL_FALLBACK | PERMIT_SYMBOL | (aliases ? ALIASES : 0), filename)
  def self.safe_load(yaml, aliases: false, filename: "") = YAML.parse_with(yaml, NIL_FALLBACK | 2 | (aliases ? ALIASES : 0), filename)
  def self.load_file(path, aliases: false) = YAML.load(File.read(path), aliases: aliases, filename: path)
  def self.safe_load_file(path, aliases: false) = YAML.safe_load(File.read(path), aliases: aliases, filename: path)
  def self.unsafe_load_file(path) = YAML.unsafe_load(File.read(path), filename: path)
end

# Psych's core_ext: every object answers #to_yaml.
class Object
  def to_yaml = YAML.dump(self)
end

Psych::VERSION = "5.4.0-spinel"
