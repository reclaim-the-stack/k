require "yaml"

strings = ["", " ", "a", "y", "Y", "n", "N", "yes", "No", "on", "OFF", "true", "null", "Null", "~", "<<",
  "1", "01", "08", "0755", "0x1f", "1_000", "1,000", "1.5", "1.", ".5", "1e3", "1.0e+3", "-", ".", "+.",
  ".inf", "-.inf", ".NaN", "1:30", "12:30:45", "2026-09-30", "2026-9-3", "2026-09-30T12:00:00Z",
  ":sym", "::", "@at", "#hash", "!bang", "&amp", "*star", "|pipe", ">gt", "%pct", "`tick", "'", "\"",
  "a: b", "a:b", "a #b", "a#b", "- a", "-a", "?", "? x", "[x]", "{x}", "x,y", "foo bar", " lead", "trail ",
  "tab\there", "line1\nline2", "trailing newline\n", "\n", "two\n\n", "unicode é ü ✓", "ångström",
  "http://example.com/a?b=c&d", "$HOME/bin", "/usr/local", "C:\\path", "some \"quoted\" text",
  "it's", "x" * 100, ("word " * 30).strip, "ends with colon:", "k8s.io/name", "--flag=1", "=", "==",
  "3000", "-1", "+1", "0b101", "0o17", "1_2", "_1", "1__2", "0.0.0.0", "10.0.0.1/8", "v1.2.3", "1.2.3"]

hash = {}
strings.each_with_index { |s, i| hash["k#{i}"] = s }
hash["nested"] = { "list" => strings.first(10), "empty" => "", "nil" => nil, "int" => 42, "neg" => -7, "float" => 3.25, "big" => 2**70, "t" => true, "f" => false }
hash["sym_key_like"] = { ":a" => 1, "yes" => 2, "1" => 3, "" => 4 }
print YAML.dump(hash)
print YAML.dump(strings)
print YAML.dump("top level string")
print YAML.dump(42)
print YAML.dump(nil)
print YAML.dump([])
print YAML.dump({})
