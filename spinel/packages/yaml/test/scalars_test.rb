require "yaml"

# Plain-scalar resolution (Psych::ScalarScanner), minus Date/Time/Symbol.
%w[~ null Null NULL yes No ON off true FALSE y n 0 -1 +7 0755 0o17 0x1F 0b101 1_000 1,000 08 1.5 1. .5 -.5 1e3
   1.0e+3 1.0e3 .inf -.Inf .NaN 1:30 1:30:15 1:30.5 . +. abc 1abc a1 v1.2.3 1.2.3 12:61 0.0.0.0].each do |s|
  p [s, YAML.unsafe_load("v: #{s}\n")["v"]]
end
p YAML.unsafe_load("v:\n")
p YAML.unsafe_load("v: ''\n")
p YAML.unsafe_load("v: !!str 123\n")
p YAML.unsafe_load("v: !!int '42'\n")
p YAML.unsafe_load("base: &b {x: 1, y: 2}\nm:\n  <<: *b\n  y: 3\nn:\n  <<: [*b, {z: 4}]\n")
p YAML.unsafe_load("s: |\n  keep\n  lines\nf: >-\n  fold\n  me\n")
p YAML.unsafe_load("--- first\n--- second\n")
