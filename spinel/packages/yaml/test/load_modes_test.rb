require "yaml"

def try(label)
  puts "#{label}: #{yield.inspect}"
rescue StandardError => e
  puts "#{label}: #{e.class}: #{e.message}"
end

aliased = "a: &x 1\nb: *x\n"
try("unsafe_load alias") { YAML.unsafe_load(aliased) }
try("load alias") { YAML.load(aliased) }
try("load alias aliases:true") { YAML.load(aliased, aliases: true) }
try("safe_load alias") { YAML.safe_load(aliased) }
try("safe_load alias aliases:true") { YAML.safe_load(aliased, aliases: true) }
try("unknown anchor") { YAML.unsafe_load("a: *nope\n") }
try("safe_load date") { YAML.safe_load("d: 2026-09-30\n") }
try("load date") { YAML.load("d: 2026-09-30\n") }
try("load time") { YAML.load("t: 2026-09-30 12:00:00 Z\n") }
try("safe_load symbol") { YAML.safe_load("s: :foo\n") }
try("quoted date is fine") { YAML.safe_load("d: '2026-09-30'\n") }
try("unsafe_load empty") { YAML.unsafe_load("") }
try("load empty") { YAML.load("") }
try("safe_load empty") { YAML.safe_load("") }
try("rescue as BadAlias") { begin; YAML.load(aliased); rescue Psych::BadAlias => e; "rescued #{e.class}"; end }
try("rescue as Psych::Exception") { begin; YAML.safe_load("d: 2026-09-30\n"); rescue Psych::Exception => e; "rescued #{e.class}"; end }
