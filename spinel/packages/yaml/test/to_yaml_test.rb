require "yaml"

config = { "context" => nil, "contexts" => {} }
print config.to_yaml
loaded = YAML.load(config.to_yaml)
loaded["contexts"]["demo"] = { "repository" => "git@github.com:acme/demo.git", "registry" => "ghcr.io" }
print loaded.to_yaml
print loaded["contexts"]["demo"]["registry"].to_yaml.delete_prefix("--- ")
print [1, "two", 3.0].to_yaml
print "multi\nline\nstring".to_yaml
begin
  YAML.load("a: [1, 2")
rescue Psych::SyntaxError => e
  puts "rescued #{e.class}: #{e.message}"
end
