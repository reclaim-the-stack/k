require "shellwords"

[
  "", "plain", "it's a \"test\" $x", "multi\nline", "ünïcode ok", "a\tb", "--flag=value",
  "rails runner 'puts User.count'", "EAGER_LOAD=false bundle exec rails console"
].each do |string|
  p Shellwords.escape(string)
  p Shellwords.shellescape(string)
  p string.shellescape
end
p Shellwords.escape(42)

p Shellwords.join(["kubectl", "exec", "it's"])
p Shellwords.shelljoin(["a", 1, "b c"])
p ["a", "b c"].shelljoin

p Shellwords.split(%(one "two three" 'four five' six\\ seven "esc\\"aped"))
p Shellwords.shellsplit("a  b\tc\nd")
p Shellwords.shellwords("a b")
p "x 'y z'".shellsplit

[%(unterminated "quote), %(also 'unterminated)].each do |line|
  Shellwords.split(line)
rescue ArgumentError => e
  p e.message
end

begin
  Shellwords.escape("nul\0")
rescue ArgumentError => e
  p e.message
end
