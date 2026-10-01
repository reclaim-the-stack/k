# Raise Interrupt on SIGINT, as CRuby does by default, see README.md.

unless RUBY_ENGINE == "spinel"
  return # CRuby raises Interrupt on SIGINT by itself
end

Signal.trap("INT") { raise Interrupt }
