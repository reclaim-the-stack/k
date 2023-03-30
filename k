#!/usr/bin/env ruby

# Known issues:
# - pbcopy doesn't work on linux

require "yaml"

K_CONFIG_FILE = "#{ENV.fetch('HOME')}/.k/config".freeze

unless File.exist?(K_CONFIG_FILE)
  puts "Generating empty config file at #{K_CONFIG_FILE}"

  k_directory = "#{ENV.fetch('HOME')}/.k"
  Dir.mkdir(k_directory) unless Dir.exist?(k_directory)

  initial_config = {
    "context" => nil,
    "contexts" => {},
  }
  File.write(K_CONFIG_FILE, initial_config.to_yaml)
end

K_CONFIG = YAML.load_file(K_CONFIG_FILE)

if (context = K_CONFIG["contexts"][K_CONFIG["context"]])
  ORGANIZATION = context.fetch("github_organization").freeze
  REPO_NAME = K_CONFIG["context"].freeze
  INTERNAL_REPO_PATH = "#{ENV.fetch('HOME')}/.k/#{REPO_NAME}".freeze
  REGISTRY = "#{context.fetch('registry')}/#{context.fetch('registry_namespace')}".freeze
  KUBECTL_CONTEXT = context.fetch("kubectl_context").freeze
  abort("Fatal: couldn't locate gitops repository at #{INTERNAL_REPO_PATH}") unless File.directory?(INTERNAL_REPO_PATH)
elsif ARGV.include?("contexts:add")
  # Do nothing - we're about to add a context!
elsif K_CONFIG["contexts"].empty?
  puts "Warning: no contexts configured. Please run `k contexts:add <github-repository>` to configure a context"
else
  puts "Error: your configured context '#{K_CONFIG['context']}' didn't match any existing contexts"
  puts "Run `k contexts` to see a list of available contexts and `k contexts:use <context>` to switch contexts"
  abort
end

def gray(string)
  $stdout.tty? ? "\e[0;90;49m#{string}\e[0m" : string
end

def green(string)
  $stdout.tty? ? "\e[0;32;49m#{string}\e[0m" : string
end

def yellow(string)
  $stdout.tty? ? "\033[33m#{string}\e[0m" : string
end

def blue(string)
  $stdout.tty? ? "\033[34m#{string}\e[0m" : string
end

def cyan(string)
  $stdout.tty? ? "\033[36m#{string}\e[0m" : string
end

def bold(string)
  $stdout.tty? ? "\e[1m#{string}\e[22m" : string
end

def in_argo_repo
  Dir.chdir INTERNAL_REPO_PATH do
    status = `git status --porcelain`

    dirty = !!status.lines.find do |line|
      line.strip[/^[MDA]/] # dirty files are "M"odified, "D"eleted or "A"dded
    end

    abort "Error: your ArgoCD repository at #{INTERNAL_REPO_PATH} needs to be in a clean state to manipulate" if dirty

    system "git pull --rebase --quiet"

    yield
  end
end

def print_commands
  # rubocop:disable Style/StringConcatenation
  puts "COMMANDS:"
  puts "k applications [<application>]" + gray(" list applications or show application details")
  puts "k config <application> [<search-string>]" + gray(" list ENV vars for an application")
  puts "k config:edit <application>" + gray(" edit ENV vars on an application")
  puts "k config:get <application> <env-var>" + gray(" prints a single environment variable value for an application")
  puts "k console <application>" + gray(" start a rails console on an application")
  puts "k dashboard <application>" + gray(" opens application dashboard in grafana")
  puts "k deploy <application>" + gray(" deploy docker image to an application (run from repo/branch you want to deploy)")
  puts "k env-to-secret <env-file> <secret-name>"
  puts "k generate" + gray(" list generate commands for creating / adding resources to applications")
  puts "k kibana <application>" + gray(" access kibana from an elastic search enabled application")
  puts "k logs <application> [<type1>, <type2>...]" + gray(" tail application logs")
  puts "k logs:search <application> [<regexp-query>]" + gray(" search application logs via grafana")
  puts "k pg" + gray(" list postgres related commands")
  puts "k redis:cli <application>" + gray(" run redis-cli on redis for an application")
  puts "k redis:failover <application>" + gray(" run FAILOVER command on the current master instance")
  puts "k releases <application>" + gray(" lists the past 15 releases for an application")
  puts "k rollback <application>" + gray(" show prompt to rollback an application")
  puts "k run <application> <command>" + gray(" run a command using a one off pod")
  puts "k secrets [<specific-secret>]" + gray(" lists secrets including usage details")
  puts "k secrets:create <secret-name>" + gray(" create a new secret")
  puts "k secrets:edit <secret-name>" + gray(" edit a secret")
  puts ""
  puts "DEBUGGING COMMANDS:"
  puts "k playground <node-name>" + gray(" open a utilities shell on a kubernetes node")
  puts "k sh <pod|deployment|statefulset>" + gray(" shell into a live deployment")
  puts "k exec <deployment> <command>" + gray(" execute a command on a live deployment")
  # rubocop:enable Style/StringConcatenation
end

PRIVATE_METHODS_BEFORE_COMMANDS = private_methods.dup.freeze

def applications
  in_argo_repo do
    applications = Dir.glob("applications/*/Chart.yaml").map { |path| path.split("/")[1] }
    requested_applications = ARGV

    if requested_applications.empty?
      puts "#{gray('===')} #{bold('Applications')}"
      puts applications
      puts ""
      puts "Run k applications <application-name> for details about a specific application"
    else
      require "yaml"

      missing_applications = requested_applications - applications
      abort "Error: #{missing_applications.join(', ')} didn't match any applications" unless missing_applications.empty?

      requested_applications.each do |application|
        puts "#{gray('===')} #{bold(application)}"
        values = YAML.load_file("applications/#{application}/values.yaml")
        scaling = values["scaling"].to_h.map do |name, data|
          name_kebab = name.gsub(/(.)([A-Z])/, '\1-\2').downcase
          "#{name_kebab}: #{data.fetch('replicas')}"
        end
        puts ""
        puts "Scaling:"
        puts scaling
        puts ""
        resources = values["resources"].to_h.map { |name, data| "#{name}: #{data['replicas']}" }
        puts "Resources:"
        puts resources
      end
    end
  end
end

alias apps applications

def clickhouse
  cluster = ARGV.delete_at(0)
  abort "Must pass name of cluster, eg. k clickhouse <cluster>" unless cluster

  require "json"

  pod = read_kubectl("kubectl get pods -l clickhouse.altinity.com/chi=#{cluster} -o name").lines.first.strip

  system "kubectl exec -it #{pod} -- clickhouse-client"
end

def contexts
  puts "#{gray('===')} #{bold('Contexts')}"
  current_context = K_CONFIG.fetch("context")
  K_CONFIG.fetch("contexts").each do |name, data|
    puts "#{name}#{' *' if name == current_context}"
  end
end

def contexts_add
  repository_url = ARGV.delete_at(0)
  unless repository_url
    puts bold "Usage"
    puts "k contexts:add <github-repository-url>"
    puts ""
    puts bold "Description"
    puts "Adds a k context. A context is a combination of:"
    puts "1. A GitHub repository containing ArgoCD platform and applications manifests"
    puts "2. A Docker registry + namespace containing Docker images to be deployed as applications"
    puts "3. A Kubernetes cluster (ie. a locally configured kubectl context)"
    exit
  end

  require "uri"
  require "fileutils"

  uri = URI(repository_url)
  abort "Error: URL must be a GitHub repository" unless uri.host == "github.com"

  puts ""
  puts "Verifying access to #{repository_url}..."

  # Verify that we have read access to the repository
  tmp_repo_path = "/tmp/k-context-add-#{Time.now.to_i}"
  unless system "git clone #{repository_url} -q #{tmp_repo_path} &> /dev/null"
    abort "Error: could clone repository #{repository_url}"
  end

  # Verify that we have write access to the repository
  write_access =
    Dir.chdir tmp_repo_path do
      test_branch_name = "write-access-test-#{Time.now.to_i}"
      system "git branch #{test_branch_name}"
      write_access = system "git push origin #{test_branch_name} -q &> /dev/null"
      system "git push -d origin #{test_branch_name} -q &> /dev/null" if write_access
      write_access
    end
  FileUtils.rm_rf tmp_repo_path
  abort "Error: failed to verify write access to #{repository_url}" unless write_access

  puts "Write access verified ✅"
  puts ""

  github_organization, repository_name = uri.path.delete_prefix("/").split("/")
  repository_name = repository_name.delete_suffix(".git")

  context_name = repository_name

  if K_CONFIG.fetch("contexts").key?(context_name)
    puts "A context named '#{context_name}' already exists"
    print "What would you like to name it instead?"
    context_name = readline.strip

    abort "Error: context name cannot be blank" if context_name.empty?
    abort "Error: context can only contain alphanumerics, dashes, and underscores" unless context_name =~ /^[a-zA-Z0-9_-]+$/
    abort "Error: context name '#{context_name}' already exists" if K_CONFIG.fetch("contexts").key?(context_name)
    puts ""
  end

  default_registry = "docker.io"
  print "Which Docker registry should be used for this context? [#{default_registry}] "
  registry = readline.strip
  registry = default_registry if registry.empty?

  print "Which Docker registry namespace should be used for this context? [#{github_organization}] "
  registry_namespace = readline.strip
  registry_namespace = github_organization if registry_namespace.empty?
  puts ""

  puts "Verifying access to registry..."
  registry_host = registry.split("/").first
  abort "Error: failed to verify access to #{registry}" unless system "docker login #{registry_host} > /dev/null"
  puts "Access to #{registry_host} verified ✅"
  puts "NOTE: write access to the #{registry}/#{registry_namespace} namespace is assumed but not verified"
  puts ""

  current_kubectl_context = `kubectl config current-context`.chomp
  kubectl_contexts = `kubectl config get-contexts -o name`.lines.map(&:chomp)
  if kubectl_contexts.empty?
    abort "Error: you don't have any kubectl contexts configured, having kubectl"\
          "connected to a Kubernetes cluster is a prerequisite to using k."
  end
  default_context = current_kubectl_context.empty? ? kubectl_contexts.first : current_kubectl_context
  print "Which kubectl context should be used for this context? [#{default_context}] "
  kubernetes_context = readline.strip
  kubernetes_context = default_context if kubernetes_context.empty?
  puts ""

  abort "Error: kubectl context '#{kubernetes_context}' does not exist" unless kubectl_contexts.include?(kubernetes_context)

  K_CONFIG.fetch("contexts")[context_name] = {
    "repository" => repository_url,
    "registry" => registry,
    "registry_namespace" => registry_namespace,
    "github_organization" => github_organization,
    "kubectl_context" => kubernetes_context,
  }
  K_CONFIG["context"] = context_name

  repository_path = "#{ENV.fetch('HOME')}/.k/#{context_name}"
  puts "Cloning self managed repository into #{repository_path}."
  system_or_die "git clone #{repository_url} #{repository_path} -q"
  puts "NOTE: k uses this repository for eg. deployments, rollbacks and secrets management. "\
       "Use your own clone for adding applications and resources via `k generate`."

  File.write(K_CONFIG_FILE, K_CONFIG.to_yaml)

  puts ""
  puts "The context '#{context_name}' was added and is now active 🚀"
end

def contexts_set
  context_name = ARGV.delete_at(0)
  abort "Must pass name of context, eg. k contexts:set <context>" unless context_name

  abort "Error: context '#{context_name}' does not exist" unless K_CONFIG.fetch("contexts").key?(context_name)

  K_CONFIG["context"] = context_name
  File.write(K_CONFIG_FILE, K_CONFIG.to_yaml)

  puts "Context '#{context_name}' is now active 🚀"
end

def kibana
  application = ARGV.delete_at(0)
  abort "Must pass name of application, eg. k kibana <application>" unless application

  # common.k8s.elastic.co/type=kibana
  # kibana.k8s.elastic.co/name=mynewsdesk-funnel

  puts "Storing kibana password in clipboard..."
  system "kubectl get secret #{application}-es-elastic-user --template={{.data.elastic}} | base64 -D | pbcopy"
  puts ""

  require "socket"

  5601.upto(5700) do |port|
    # If we can connect to the port another kibana is already active and we skip to the next port
    next if TCPSocket.new("127.0.0.1", port).close.nil? rescue false # rubocop:disable Style/RescueModifier

    puts "Making kibana accessible at: http://localhost:#{port}/app/monitoring#/overview"
    puts "Login with username 'elastic' and paste the password from your clipboard"
    puts ""
    system "kubectl port-forward service/#{application}-kb-http #{port}:5601"
  end
end

# NOTE: not ready for use and we might not need this
def config_set
  application = ARGV.delete_at(0)
  abort "Must pass name of application, eg. k logs <application> <env-vars>" unless application
  abort "Must pass some ENV vars to set, eg. k logs <application> ENV_VAR=value" if ARGV.empty?

  # env_vars = ARGV.each do |env_pair|
  #   match = env_pair.match(/([A-Z]+)=(.+)/m)
  #   abort "Error: #{env_pair} is not a valid ENV var" unless match
  #   name = match[1]
  #   value = match[2]
  # end
end

def dashboard
  application = ARGV.delete_at(0)
  abort "Must pass name of application, eg. k dashboard <application>" unless application

  require "uri"

  grafana_query = URI.encode_www_form(
    {
      "orgId" => "1",
      "from" => "now-1h",
      "to" => "now",
      "var-namespace" => "default",
      "var-deployment" => "#{application}-web",
    },
  )

  # TODO: replace mynewsdesk.dev reference
  grafana_url = "https://grafana.mynewsdesk.dev/d/Vv9aFgxVk/mynewsdesk-application?#{grafana_query}"

  puts "Opening #{grafana_url} ..."
  system "open \"#{grafana_url}\""
end

def logs
  application = ARGV.delete_at(0)
  abort "Must pass name of application, eg. k logs <application> [<type1>, <type2>...]" unless application
  abort "Please install kail (brew install kail) for logs support" unless system("which kail > /dev/null")

  require "json"

  deployments_json = `kubectl get deployments -o json -l argocd.argoproj.io/instance=#{application}`
  deployments = JSON.parse(deployments_json).fetch("items")
  abort "Couldn't find any deployments for the application #{application}" if deployments.empty?

  deployment_names = deployments.map { |deployment| deployment.fetch("metadata").fetch("name") }
  unless ARGV.empty?
    deployment_names.select! { |deployment| ARGV.include? deployment.delete_prefix("#{application}-") }
    abort "couldn't find any deployments matching #{ARGV.join(', ')}" if deployment_names.empty?
  end

  kail_arguments = deployment_names.map { |name| "-d #{name}" }.join(" ")

  puts "Tailing logs from #{deployment_names.join(', ')}..."
  exec "kail #{kail_arguments}"
end

def logs_search
  application = ARGV.delete_at(0)
  abort "Must pass name of application, eg. k logs:search <application> [<type1>, <type2>...]" unless application

  require "json"

  deployments_json = `kubectl get deployments -o json -l argocd.argoproj.io/instance=#{application}`
  deployments = JSON.parse(deployments_json).fetch("items")
  abort "Couldn't find any deployments for the application #{application}" if deployments.empty?

  require "uri"

  deployment_names = deployments.map { |deployment| deployment.fetch("metadata").fetch("name") }

  grafana_query = URI.encode_www_form_component(
    {
      "datasource" => "loki",
      "queries" =>
      [
        {
          "refId" => "Filter",
          "datasource" => { "type" => "loki", "uid" => "loki" },
          "editorMode" => "builder",
          "expr" => %({app=~"#{deployment_names.join('|')}"} |~ `#{ARGV.join(' ')}`),
          "queryType" => "range",
        },
      ],
      "range" => { "from" => "now-1h", "to" => "now" },
    }.to_json,
  )
  # TODO: replace mynewsdesk.dev reference
  grafana_url = "https://grafana.mynewsdesk.dev/explore?left=#{grafana_query}"

  puts "Opening #{grafana_url} ..."
  system "open #{grafana_url}"
end

module Pg
  def self.exec_on_primary(cluster, command)
    primary_pod_name = `kubectl get pod --selector=postgres-operator.crunchydata.com/role=master,postgres-operator.crunchydata.com/cluster=#{cluster} -o name`.chomp
    system "kubectl exec #{primary_pod_name} -it -c database -- #{command}"
  end

  def self.query_on_primary(cluster, query)
    uri = `kubectl get secret #{cluster}-pguser-#{cluster} -o go-template='{{.data.uri | base64decode}}'`
    exec_on_primary cluster, %(psql '#{uri}' -c "#{query}")
  end
end

def pg
  puts "Note: <cluster-name> is the same as <application-name> when following standard naming conventions."
  puts ""
  puts "POSTGRES COMMANDS:"
  puts "pg:failover <cluster-name>"
  puts "pg:patroni <cluster-name> <patroni-command>"
  puts "pg:pods"
  puts "pg:primaries"
  puts "pg:proxy" + gray(" connect to any Kubernetes Postgres instance via localhost")
  puts "pg:psql <cluster-name>"
  puts "pg:resources <cluster-name>"
  puts "pg:uri <cluster-name>"
  puts ""
  puts "POSTGRES DIAGNOSTICS:"
  puts "pg:bloat <cluster-name>"
  puts "pg:cache <cluster-name>"
  puts "pg:index_usage <cluster-name>"
  puts "pg:seq_scans <cluster-name>"
  puts "pg:table_size <cluster-name>"
  puts "pg:unused_indexes <cluster-name>"
end

def pg_failover
  cluster = ARGV.delete_at(0)
  abort "Must pass name of cluster, eg. k pg:failover <cluster-name>" unless cluster

  system %(kubectl annotate postgrescluster #{cluster} --overwrite postgres-operator.crunchydata.com/trigger-switchover="$(date)") # rubocop:disable Layout/LineLength
end

def pg_patroni
  cluster = ARGV.delete_at(0)
  abort "Must pass name of cluster, eg. k pg:patroni <cluster-name> <command>" unless cluster

  patroni_command = ARGV.delete_at(0) || "--help"

  Pg.exec_on_primary(cluster, "patronictl #{patroni_command}")
end

def pg_pods
  system "kubectl get pods -o wide --selector=postgres-operator.crunchydata.com/data=postgres"
end

def pg_primaries
  system "kubectl get pods -o wide --selector=postgres-operator.crunchydata.com/role=master"
end

def pg_proxy
  exec "k_pg_proxy"
end

def pg_psql
  cluster = ARGV.delete_at(0)
  abort "Must pass name of cluster, eg. k pg:psql <cluster-name>" unless cluster

  require "json"
  require "base64"

  secret = JSON.parse(`kubectl get secret #{cluster}-pguser-#{cluster} -o json`).fetch("data")

  use_pg_bouncer = secret.key?("pgbouncer-uri")
  uri = Base64.strict_decode64(secret.fetch(use_pg_bouncer ? "pgbouncer-uri" : "uri"))
  puts "Connecting via PgBouncer..." if use_pg_bouncer

  Pg.exec_on_primary(cluster, "psql '#{uri}'")
end

def pg_resources
  cluster = ARGV.delete_at(0)
  abort "Must pass name of cluster, eg. k pg:status <cluster-name>" unless cluster

  system "kubectl get all --selector=postgres-operator.crunchydata.com/cluster=#{cluster}"
  puts ""
  system "kubectl get secrets --selector=postgres-operator.crunchydata.com/cluster=#{cluster}"
end

def pg_uri
  cluster = ARGV.delete_at(0)
  abort "Must pass name of cluster, eg. k pg:uri <cluster-name>" unless cluster

  require "json"
  require "base64"

  secret = JSON.parse(`kubectl get secret #{cluster}-pguser-#{cluster} -o json`).fetch("data")
  uri = Base64.strict_decode64(secret.fetch("uri"))
  pgbouncer_uri = Base64.strict_decode64(secret.fetch("pgbouncer-uri")) if secret.key?("pgbouncer-uri")
  puts "Postgres URI: #{uri}"
  puts "PgBouncer URI: #{uri}" if pgbouncer_uri
end

def pg_bloat
  cluster = ARGV.delete_at(0)
  abort "Must pass name of cluster, eg. pg:bloat <cluster-name>" unless cluster

  Pg.query_on_primary cluster, <<~SQL
    WITH constants AS (
      SELECT current_setting('block_size')::numeric AS bs, 23 AS hdr, 4 AS ma
    ), bloat_info AS (
      SELECT
        ma,bs,schemaname,tablename,
        (datawidth+(hdr+ma-(case when hdr%ma=0 THEN ma ELSE hdr%ma END)))::numeric AS datahdr,
        (maxfracsum*(nullhdr+ma-(case when nullhdr%ma=0 THEN ma ELSE nullhdr%ma END))) AS nullhdr2
      FROM (
        SELECT
          schemaname, tablename, hdr, ma, bs,
          SUM((1-null_frac)*avg_width) AS datawidth,
          MAX(null_frac) AS maxfracsum,
          hdr+(
            SELECT 1+count(*)/8
            FROM pg_stats s2
            WHERE null_frac<>0 AND s2.schemaname = s.schemaname AND s2.tablename = s.tablename
          ) AS nullhdr
        FROM pg_stats s, constants
        GROUP BY 1,2,3,4,5
      ) AS foo
    ), table_bloat AS (
      SELECT
        schemaname, tablename, cc.relpages, bs,
        CEIL((cc.reltuples*((datahdr+ma-
          (CASE WHEN datahdr%ma=0 THEN ma ELSE datahdr%ma END))+nullhdr2+4))/(bs-20::float)) AS otta
      FROM bloat_info
      JOIN pg_class cc ON cc.relname = bloat_info.tablename
      JOIN pg_namespace nn ON cc.relnamespace = nn.oid AND nn.nspname = bloat_info.schemaname AND nn.nspname <> 'information_schema'
    ), index_bloat AS (
      SELECT
        schemaname, tablename, bs,
        COALESCE(c2.relname,'?') AS iname, COALESCE(c2.reltuples,0) AS ituples, COALESCE(c2.relpages,0) AS ipages,
        COALESCE(CEIL((c2.reltuples*(datahdr-12))/(bs-20::float)),0) AS iotta -- very rough approximation, assumes all cols
      FROM bloat_info
      JOIN pg_class cc ON cc.relname = bloat_info.tablename
      JOIN pg_namespace nn ON cc.relnamespace = nn.oid AND nn.nspname = bloat_info.schemaname AND nn.nspname <> 'information_schema'
      JOIN pg_index i ON indrelid = cc.oid
      JOIN pg_class c2 ON c2.oid = i.indexrelid
    )
    SELECT
      type, schemaname, object_name, bloat, pg_size_pretty(raw_waste) as waste
    FROM
    (SELECT
      'table' as type,
      schemaname,
      tablename as object_name,
      ROUND(CASE WHEN otta=0 THEN 0.0 ELSE table_bloat.relpages/otta::numeric END,1) AS bloat,
      CASE WHEN relpages < otta THEN '0' ELSE (bs*(table_bloat.relpages-otta)::bigint)::bigint END AS raw_waste
    FROM
      table_bloat
        UNION
    SELECT
      'index' as type,
      schemaname,
      tablename || '::' || iname as object_name,
      ROUND(CASE WHEN iotta=0 OR ipages=0 THEN 0.0 ELSE ipages/iotta::numeric END,1) AS bloat,
      CASE WHEN ipages < iotta THEN '0' ELSE (bs*(ipages-iotta))::bigint END AS raw_waste
    FROM
      index_bloat) bloat_summary
    ORDER BY raw_waste DESC, bloat DESC
  SQL
end

def pg_cache
  cluster = ARGV.delete_at(0)
  abort "Must pass name of cluster, eg. pg:cache <cluster-name>" unless cluster

  Pg.query_on_primary cluster, <<~SQL
    SELECT
      'index hit rate' AS name,
      (sum(idx_blks_hit)) / nullif(sum(idx_blks_hit + idx_blks_read),0) AS ratio
    FROM pg_statio_user_indexes
    UNION ALL
    SELECT
      'table hit rate' AS name,
      sum(heap_blks_hit) / nullif(sum(heap_blks_hit) + sum(heap_blks_read),0) AS ratio
    FROM pg_statio_user_tables
  SQL
end

def pg_index_usage
  cluster = ARGV.delete_at(0)
  abort "Must pass name of cluster, eg. pg:index_usage <cluster-name>" unless cluster

  Pg.query_on_primary cluster, <<~SQL
    SELECT relname,
      CASE idx_scan
        WHEN 0 THEN 'Insufficient data'
        ELSE (100 * idx_scan / (seq_scan + idx_scan))::text
      END percent_of_times_index_used,
      n_live_tup rows_in_table
    FROM
      pg_stat_user_tables
    ORDER BY
      n_live_tup DESC
  SQL
end

def pg_seq_scans
  cluster = ARGV.delete_at(0)
  abort "Must pass name of cluster, eg. pg:seq_scans <cluster-name>" unless cluster

  Pg.query_on_primary cluster, <<~SQL
    SELECT relname AS name,
      seq_scan as count
    FROM
    pg_stat_user_tables
    ORDER BY seq_scan DESC
  SQL
end

def pg_table_size
  cluster = ARGV.delete_at(0)
  abort "Must pass name of cluster, eg. pg:table_size <cluster-name>" unless cluster

  Pg.query_on_primary cluster, <<~SQL
    SELECT c.relname AS name,
      pg_size_pretty(pg_table_size(c.oid)) AS size
    FROM pg_class c
    LEFT JOIN pg_namespace n ON (n.oid = c.relnamespace)
    WHERE n.nspname NOT IN ('pg_catalog', 'information_schema')
    AND n.nspname !~ '^pg_toast'
    AND c.relkind='r'
    ORDER BY pg_table_size(c.oid) DESC
  SQL
end

def pg_unused_indexes
  cluster = ARGV.delete_at(0)
  abort "Must pass name of cluster, eg. pg:unused_indexes <cluster-name>" unless cluster

  Pg.query_on_primary cluster, <<~SQL
    SELECT
      schemaname || '.' || relname AS table,
      indexrelname AS index,
      pg_size_pretty(pg_relation_size(i.indexrelid)) AS index_size,
      idx_scan as index_scans
    FROM pg_stat_user_indexes ui
    JOIN pg_index i ON ui.indexrelid = i.indexrelid
    WHERE NOT indisunique AND idx_scan < 50 AND pg_relation_size(relid) > 5 * 8192
    ORDER BY pg_relation_size(i.indexrelid) / nullif(idx_scan, 0) DESC NULLS FIRST,
    pg_relation_size(i.indexrelid) DESC
  SQL
end

# TODO: should have a configurable timeout (sleep duration) for long running commands
def run
  application = ARGV.delete_at(0)
  abort "Must pass name of application, eg. k run <application> <command>" unless application
  abort "Must pass command to run, eg. k run <application> <command>" if ARGV.empty?

  require "json"

  deployments_json = `kubectl get deployments -o json -l argocd.argoproj.io/instance=#{application}`
  deployments = JSON.parse(deployments_json).fetch("items")
  abort "Couldn't find any deployments for the application #{application}" if deployments.empty?

  require "securerandom"

  deployment =
    deployments.find { |d| d.fetch("metadata").fetch("name").end_with?("-web") } ||
    deployments.first
  pod_spec = deployment.fetch("spec").fetch("template").fetch("spec")
  container = pod_spec.fetch("containers").first
  pod_name = "#{application}-run-#{SecureRandom.hex(3)}"

  pod_template = {
    apiVersion: "v1",
    kind: "Pod",
    metadata: {
      name: pod_name,
    },
    spec: {
      restartPolicy: "Never",
      imagePullSecrets: pod_spec["imagePullSecrets"] || [],
      containers: [
        {
          name: "run",
          image: container.fetch("image"),
          envFrom: container["envFrom"] || [],
          env: container["env"] || {},
          imagePullPolicy: "IfNotPresent",
          command: %w[sleep 3600], # shutdown the pod after 1 hour
        },
      ],
    },
  }

  puts "Creating pod #{pod_name}..."
  system("echo '#{pod_template.to_json}' | kubectl apply -f -") || abort("failed to create pod")

  unless system("kubectl wait pod #{pod_name} --for=condition=ContainersReady --timeout=120s > /dev/null")
    puts "failed to start pod, attempting to delete it..."
    system "kubectl delete pod #{pod_name} --wait=false"
    abort
  end

  command = ARGV.join(" ")
  puts "Running #{command} on #{pod_name}..."
  command_success = system "kubectl exec #{pod_name} -it -- sh -c '#{command}'"
  system("kubectl delete pod #{pod_name} --wait=false") || abort("failed to delete the pod")
  abort unless command_success
end

def console
  application = ARGV.delete_at(0)
  abort "Must pass name of application, eg. k console <application>" unless application

  system %(#{__dir__}/k run #{application} "EAGER_LOAD=false bin/rails console")
end

def config
  application = ARGV.delete_at(0)
  grep_string = ARGV.delete_at(0)
  abort "Must pass name of application, eg. k config <application>" unless application

  in_argo_repo do
    app_path = "applications/#{application}"
    abort "Error: could not find a ArgoCD application at #{INTERNAL_REPO_PATH}/#{app_path}" unless File.directory?(app_path)

    values_path = "#{app_path}/values.yaml"
    abort "Error: could not find helm values at #{INTERNAL_REPO_PATH}/#{values_path}" unless File.exist?(values_path)

    require "base64"
    require "yaml"

    values = YAML.load_file(values_path)

    env = {}

    shared_secrets = (values["envFrom"] || []).map { |config| config.fetch("secretRef").fetch("name") }
    shared_secrets.each do |secret_name|
      secret = YAML.safe_load(`kubectl get secret #{secret_name} -o yaml`)
      secret_env = secret.fetch("data").transform_values do |value|
        { value: Base64.strict_decode64(value), source: secret_name }
      end
      env.merge!(secret_env)
    end

    if (values_env = values["env"])
      values_env.each do |env_entry|
        name = env_entry.fetch("name")
        if (value = env_entry["value"])
          env[name] = { value: value, source: "values.yaml" }
        elsif (value_from = env_entry["valueFrom"])
          if (secret_ref = value_from["secretKeyRef"])
            secret_name = secret_ref.fetch("name")
            secret_key = secret_ref.fetch("key")
            secret = YAML.safe_load(`kubectl get secret #{secret_name} -o yaml`)
            value = Base64.strict_decode64(secret.fetch("data").fetch(secret_key))
            env[name] = { value: value, source: "values.yaml ref: #{secret_name}.#{secret_key}" }
          else
            raise "not sure how to parse env entry in #{values_path}: #{env_entry}"
          end
        else
          raise "not sure how to parse env entry in #{values_path}: #{env_entry}"
        end
      end
    end

    output = env.sort.map do |name, entry|
      value = entry.fetch(:value)
      source = entry[:source]
      string = "#{green(name)}: #{value.to_yaml.delete_prefix('--- ').chomp}"
      string << gray(" # #{source}") if source
      string
    end

    output = output.grep(Regexp.new(grep_string)) if grep_string

    if $stdout.tty? && grep_string.nil?
      puts "#{gray('===')} #{bold(application.to_s)}"
      puts ""
      puts "Inherited secrets:"
      shared_secrets.reverse.each { |secret| puts gray("  #{secret}") }
      puts ""
    end
    puts output
  end
end

def config_edit
  application = ARGV.delete_at(0)
  abort "Must pass name of application, eg. k config:edit <application>" unless application

  in_argo_repo do
    app_path = "applications/#{application}"
    abort "Error: could not find a ArgoCD application at #{INTERNAL_REPO_PATH}/#{app_path}" unless File.directory?(app_path)

    values_path = "#{app_path}/values.yaml"
    abort "Error: could not find helm values at #{INTERNAL_REPO_PATH}/#{values_path}" unless File.exist?(values_path)

    require "yaml"

    values = YAML.load_file(values_path)

    shared_secrets = (values["envFrom"] || []).map { |config| config.fetch("secretRef").fetch("name") }.reverse
    puts ""
    puts "#{application} can be configured via one of its inherited shared secrets or directly via its application environment, which would you like to edit?" # rubocop:disable Layout/LineLength
    puts "1. Application ENV #{gray('(values.yaml)')}"
    shared_secrets.each_with_index { |secret, i| puts "#{i + 2}. #{secret} #{gray('(shared secret)')}" }
    puts ""

    print "> "
    input = readline.to_i
    puts ""

    case input
    when 0
      exit
    when 1
      puts "To edit #{application} environment via values.yaml please manually edit https://github.com/#{ORGANIZATION}/#{REPO_NAME}/blob/master/applications/#{application}/values.yaml and open a Pull Request for review." # rubocop:disable Layout/LineLength
    else
      selected_secret = shared_secrets[input - 2]
      puts "Editing shared secret: #{selected_secret}..."
      puts ""
      exec "k secrets:edit #{selected_secret}"
    end
  end
end

def config_get
  application = ARGV.delete_at(0)
  env_var = ARGV.delete_at(0)

  abort "Must pass name of application and an environment variable, eg. k config:get <application> <env-var>" unless application
  abort "Must pass name of application, eg. k config:get <application>" unless application

  in_argo_repo do
    app_path = "applications/#{application}"
    abort "Error: could not find a ArgoCD application at #{INTERNAL_REPO_PATH}/#{app_path}" unless File.directory?(app_path)

    values_path = "#{app_path}/values.yaml"
    abort "Error: could not find helm values at #{INTERNAL_REPO_PATH}/#{values_path}" unless File.exist?(values_path)

    require "base64"
    require "yaml"

    values = YAML.load_file(values_path)

    env = {}

    shared_secrets = (values["envFrom"] || []).map { |config| config.fetch("secretRef").fetch("name") }
    shared_secrets.each do |secret_name|
      secret = YAML.safe_load(`kubectl get secret #{secret_name} -o yaml`)
      secret_env = secret.fetch("data").transform_values do |value|
        { value: Base64.strict_decode64(value), source: secret_name }
      end
      env.merge!(secret_env)
    end

    if (values_env = values["env"])
      values_env.each do |env_entry|
        name = env_entry.fetch("name")
        if (value = env_entry["value"])
          env[name] = { value: value, source: "values.yaml" }
        elsif (value_from = env_entry["valueFrom"])
          if (secret_ref = value_from["secretKeyRef"])
            secret_name = secret_ref.fetch("name")
            secret_key = secret_ref.fetch("key")
            secret = YAML.safe_load(`kubectl get secret #{secret_name} -o yaml`)
            value = Base64.strict_decode64(secret.fetch("data").fetch(secret_key))
            env[name] = { value: value, source: "values.yaml ref: #{secret_name}.#{secret_key}" }
          else
            raise "not sure how to parse env entry in #{values_path}: #{env_entry}"
          end
        else
          raise "not sure how to parse env entry in #{values_path}: #{env_entry}"
        end
      end
    end

    puts env[env_var][:value] if env[env_var]
  end
end

def deploy
  application = ARGV.delete_at(0)
  abort "Must pass name of application, eg. k deploy <application>" unless application

  git_sha = ARGV.delete_at(0)
  puts "Deprecation Warning: explicit git SHA argument has been removed in favour of using the current git context" if git_sha

  git_sha = `git rev-parse HEAD`.chomp
  abort "Error: couldn't fetch git-sha from current working dir, not in a git directory?" if git_sha.empty?

  commit_author = `git log -1 --pretty=%an`.chomp
  commit_email = `git log -1 --pretty=%ae`.chomp
  commit_subject = `git log -1 --pretty=%s`.chomp

  in_argo_repo do
    chart_yaml_path = "applications/#{application}/Chart.yaml"
    abort "Error: couldn't find app chart at #{INTERNAL_REPO_PATH}/#{chart_yaml_path}" unless File.exist?(chart_yaml_path)

    values_yaml_path = "applications/#{application}/values.yaml"
    abort "Error: couldn't find app configuration at #{INTERNAL_REPO_PATH}/#{values_yaml_path}" unless File.exist?(values_yaml_path)

    # eg. europe-north1-docker.pkg.dev/kubernetes-367912/mynewsdesk/mynewsdesk:sha-31e762a6c69881d4df792ab64da3c8cb58842cdb
    image = `yq .image #{values_yaml_path}`.chomp
    repository, _tag = image.split("/").last.split(":")
    new_image = "#{REGISTRY}/#{repository}:sha-#{git_sha}"

    puts "Verifying existence of image: #{new_image}"
    1.upto(60) do |second|
      # NOTE: we have seen docker manifest inspect fail randomly even when the image exists, possibly a bug in the registry
      break if system "docker manifest inspect #{new_image} > /dev/null"

      abort "Error: Timed out waiting for #{new_image}, maybe something's wrong with the docker build?" if second == 60

      print "."
      sleep 1
    end

    puts "--- Updating Helm chart image and app version"

    system_or_die %(yq -i ".appVersion = \\"#{git_sha}\\"" #{chart_yaml_path})
    system_or_die %(yq -i ".image = \\"#{new_image}\\"" #{values_yaml_path})
    system_or_die %(yq -i ".lastChange = \\"Deploy #{git_sha}\\"" #{values_yaml_path})

    puts "--- Pushing changes to gitops repo"

    status = `git status --porcelain`
    clean = !status.lines.find do |line|
      line.strip[/^[MDA]/] # dirty files are "M"odified, "D"eleted or "A"dded
    end
    if clean
      puts "Your branch is up to date with 'origin/master'. It appears this revision is already deployed."
      exit
    end

    system_or_die %(git commit --author="#{commit_author} <#{commit_email}>" -a -F - <<EOF

#{application}: Deploy "#{commit_subject}"

Github link: https://github.com/#{ORGANIZATION}/#{repository}/commit/#{git_sha}
EOF)

    safe_git_push

    puts "+++ Tracking deployment progress"

    if ENV["BUILDKITE"] == "true"
      # TODO: replace mynewsdesk.dev reference
      system %(
        buildkite-agent annotate \
        "Track ArgoCD deployment at https://argocd.mynewsdesk.dev/applications/argocd/#{application}" \
        --style info
      )
    end

    puts "Waiting for ArgoCD to deploy the new image:"
    puts new_image

    1.upto(120) do |second|
      deployments = `
        kubectl get deployments \
        -l argocd.argoproj.io/instance=#{application} \
        -o=jsonpath="{.items[*].spec.template.spec.containers[*].image}"
      `
      break if deployments.include?(new_image)

      abort "Error: Timed out waiting for new image deployment" if second == 120

      sleep 1
    end
  end
end

# NOTE: Not ready for use yet, we'll encourage manual editing of values.yaml for now
def env_edit
  application = ARGV.delete_at(0)
  abort "Must pass name of application, eg. k edit-env <application>" unless application
  abort "Missing $EDITOR environment variable, eg: export EDITOR='code --wait --new-window'" unless ENV.key?("EDITOR")

  in_argo_repo do
    values_yaml_path = "applications/#{application}/values.yaml"
    abort "Error: couldn't find app configuration at #{INTERNAL_REPO_PATH}/#{values_yaml_path}" unless File.exist?(values_yaml_path)

    require "yaml"

    values = YAML.load_file(values_yaml_path)
    original_env = values.slice("envFrom", "env")

    # Write temporary file and launch editor
    tmp_file = "/tmp/#{application}.yaml"
    File.write tmp_file, original_env.to_yaml.delete_prefix("---\n")
    system "#{ENV.fetch('EDITOR')} #{tmp_file}"

    new_env = YAML.load_file(tmp_file)
    File.delete(tmp_file)

    if new_env == original_env
      puts "No changes detected, skipping..."
      exit
    end

    new_values = values.merge(new_env.slice("envFrom", "env"))

    puts "NOTE: this command doesn't actually commit anything yet but here is your edited values.yaml:"
    puts new_values.to_yaml.delete_prefix("---\n")
  end
end

def releases
  application = ARGV.delete_at(0)
  abort "Must pass name of application, eg. k releases <application>" unless application

  require "time"

  in_argo_repo do
    releases = lookup_latest_releases(application)
    longest_subject = releases.map(&:subject).max_by(&:length)

    # rubocop:disable Style/StringConcatenation
    puts gray("=== ") + bold(application) + bold(" Releases")
    puts ""
    puts gray("Version".ljust(13) + "Time".ljust(21) + "Subject".ljust(longest_subject.length + 2) + "Author")
    releases.each do |release|
      time_to_show =
        if (Time.now - release.time) < 86_400 # within the last 24 hours
          release.relative_time.ljust(19)
        else
          release.time.strftime("%Y-%m-%d %H:%M:%S")
        end
      puts "#{bold(release.pretty_sha)}  #{green(time_to_show)}  #{release.subject.ljust(longest_subject.length)}  #{cyan(release.author)}"
    end
    # rubocop:enable Style/StringConcatenation
  end
end

def rollback
  application = ARGV.delete_at(0)
  abort "Must pass name of application, eg. k rollback <application>" unless application

  require "time"

  in_argo_repo do
    releases = lookup_latest_releases(application)
    longest_subject = releases.map(&:subject).max_by(&:length)

    # rubocop:disable Style/StringConcatenation
    puts gray("=== ") + bold(application) + bold(" Rollback")
    puts ""
    puts gray("    Version".ljust(17) + "Time".ljust(21) + "Subject".ljust(longest_subject.length + 2) + "Author")
    releases.each.with_index do |release, index|
      adjusted_index = "#{index}.".ljust(3)
      version = index == 0 ? "    #{release.pretty_sha}".ljust(15) : "#{bold(adjusted_index)} #{release.pretty_sha}"
      time_to_show =
        if (Time.now - release.time) < 86_400 # within the last 24 hours
          release.relative_time.ljust(19)
        else
          release.time.strftime("%Y-%m-%d %H:%M:%S")
        end
      puts "#{version}  #{green(time_to_show)}  #{release.subject.ljust(longest_subject.length)}  #{cyan(release.author)}"
    end
    puts ""
    # rubocop:enable Style/StringConcatenation

    number_of_choices = releases.length - 1
    print "Which version would you like to rollback to [1-#{number_of_choices}]: "
    index = readline.to_i
    selected_release = releases[index]
    abort "Error: Selection must be a number between 1 and #{number_of_choices}" unless index > 0 && selected_release

    puts ""
    releases_to_undo = releases[0..index-1]
    puts "Note: This will undo the following previous releases: #{releases_to_undo.map(&:pretty_sha).join(' ')}"
    print "Confirm rollback to version #{bold(selected_release.pretty_sha)} [y/N] "
    choice = readline.chomp
    puts ""

    unless choice.upcase == "Y"
      puts "Rollback skipped!"
      exit
    end

    puts "Rolling back..."
    system_or_die "git show #{selected_release.sha}:applications/#{application}/values.yaml > applications/#{application}/values.yaml"
    system_or_die %(git commit -a -m "#{application}: rollback to #{selected_release.sha}" --quiet)
    safe_git_push

    puts ""
    puts "Successfully pushed the rollback to version #{selected_release.pretty_sha}."
    # TODO: replace mynewsdesk.dev reference
    puts "Follow progress at: https://argocd.mynewsdesk.dev/applications/argocd/#{application}?resource=health%3AProgressing"
  end
end

def secrets
  require "yaml"

  specific_secret = ARGV.delete_at(0)

  in_argo_repo do
    application_secrets = Dir.glob("applications/*/values.yaml").each_with_object({}) do |path, hash|
      application = path.split("/")[1]
      YAML.load_file(path)["envFrom"].each do |entry|
        secret = entry.fetch("secretRef").fetch("name")
        hash[secret] ||= []
        hash[secret] << application
      end
    end

    if specific_secret
      unless File.exist?("applications/shared-secrets/#{specific_secret}.yaml")
        abort "Error: no secret named '#{specific_secret}' found in repo"
      end

      puts bold(specific_secret)
      application_secrets[specific_secret]&.each do |application|
        puts gray("  #{application}")
      end
      puts ""
    else
      puts "Available shared secrets:"
      puts ""
      Dir.glob("applications/shared-secrets/*.yaml").each do |secret_path|
        next unless YAML.load_file(secret_path).fetch("spec").fetch("template")["type"] == "opaque"

        secret = File.basename(secret_path, ".yaml")
        puts bold(secret)
        application_secrets[secret]&.each do |application|
          puts gray("  #{application}")
        end
        puts ""
      end
    end

    puts "Use k secrets:edit #{specific_secret || '<secret-name>'} to edit"
  end
end

def secrets_edit
  shared_secret = ARGV.delete_at(0)
  abort "Must pass name of secret, eg. k secrets:edit <shared-secret-name>" unless shared_secret
  abort "Missing $EDITOR environment variable, eg: export EDITOR='code --wait --new-window'" unless ENV.key?("EDITOR")

  in_argo_repo do
    shared_secret_path = "applications/shared-secrets/#{shared_secret}.yaml"
    abort "No shared secret found at '#{shared_secret_path}'" unless File.exist?(shared_secret_path)

    require "yaml"
    require "base64"

    original_secret = YAML.safe_load(`kubectl get secret #{shared_secret} -o yaml`)
    original_env = original_secret.fetch("data").transform_values(&Base64.method(:strict_decode64))

    # Write temporary file and launch editor
    tmp_file = "/tmp/#{shared_secret}.yaml"
    File.write tmp_file, original_env.to_yaml.delete_prefix("---\n")
    system "#{ENV.fetch('EDITOR')} #{tmp_file}"

    new_env = YAML.load_file(tmp_file)
    File.delete(tmp_file)

    if new_env == original_env
      puts "No changes detected, skipping..."
      exit
    end

    data = new_env.transform_values(&:to_s).transform_values(&Base64.method(:strict_encode64))
    original_secret["data"] = data

    File.write(tmp_file, original_secret.to_yaml)
    system "kubeseal -f #{tmp_file} -o yaml > #{shared_secret_path}"
    File.delete tmp_file

    changed_variables = new_env.keys.select do |name|
      original_env[name] && original_env[name] != new_env[name]
    end
    added_variables = new_env.keys - original_env.keys
    deleted_variables = original_env.keys - new_env.keys

    commit_message = "shared-secrets: edited #{shared_secret}\n\n"
    commit_message << "Changed: #{changed_variables.join(' ')}\n" unless changed_variables.empty?
    commit_message << "Added: #{added_variables.join(' ')}\n" unless added_variables.empty?
    commit_message << "Deleted: #{deleted_variables.join(' ')}\n" unless deleted_variables.empty?

    puts commit_message

    system %(git commit -a -m "#{commit_message}" --quiet)
    safe_git_push
  end
end

def secrets_create
  secret = ARGV.delete_at(0)
  abort "Must pass name of the new secret, eg. k secrets:create <secret-name>" unless secret
  abort "Missing $EDITOR environment variable, eg: export EDITOR='code --wait --new-window'" unless ENV.key?("EDITOR")

  require "yaml"
  require "base64"

  in_argo_repo do
    secret_path = "applications/shared-secrets/#{secret}.yaml"
    if File.exist?(secret_path)
      abort "Error: A secret named '#{secret}' already exists, run 'k secrets:edit #{secret}' to edit it"
    end

    tmp_file = "/tmp/#{secret}.yaml"
    File.write(
      tmp_file,
      <<~YAML,
        # Add some initial ENV variable key/value pairs in YAML format, eg:
        PLACEHOLDER: some-value
      YAML
    )

    system "#{ENV.fetch('EDITOR')} #{tmp_file}"

    new_env = YAML.load_file(tmp_file)
    File.delete(tmp_file)

    data = new_env.transform_values(&:to_s).transform_values(&Base64.method(:strict_encode64))

    secret_yaml = {
      "apiVersion" => "v1",
      "kind" => "Secret",
      "metadata" => { "name" => secret },
      "type" => "opaque",
      "data" => data,
    }.to_yaml

    File.write tmp_file, secret_yaml
    system "kubeseal -f #{tmp_file} -o yaml > #{secret_path}"
    File.delete tmp_file

    system "git add #{secret_path}"
    system %(git commit -m "shared-secrets: add #{secret}" --quiet)
    safe_git_push

    puts "Successfully created the secret '#{secret}'"
  end
end

def sh
  resource = ARGV.delete_at(0)
  abort "Must pass name of a deployment, statefulset or pod, eg. k sh <deployment|statefulset|pod>" unless resource

  resource_type =
    if system("kubectl get pods/#{resource} &> /dev/null")
      "pods"
    elsif system("kubectl get deployments/#{resource} &> /dev/null")
      "deployments"
    elsif system("kubectl get statefulsets/#{resource} &> /dev/null")
      "statefulsets"
    else
      abort "Error: '#{resource_type}' not found among pods, deployments or statefulsets"
    end

  exec "kubectl exec -it #{resource_type}/#{resource} -- sh"
end

def _exec
  deployment = ARGV.delete_at(0)
  abort "Must pass name of deployment, eg. k exec <deployment>" unless deployment
  abort "Must pass a command to run, eg. k exec <deployment> <command>" if ARGV.empty?

  exec "kubectl exec -it deployments/#{deployment} -- #{ARGV.join(' ')}"
end

def nodes
  system "kubectl get nodes -o wide"
end

def verify
  system "helm template . | kubectl apply --dry-run=server -f -"
end

def playground
  node_hostname =
    if ARGV.empty?
      workers = `kubectl get nodes -o name`.split("\n")
      worker_one = workers.find { |name| name.include?("worker-1") }
      abort "Error: no worker-1 node found" unless worker_one

      worker_one = worker_one.delete_prefix("node/")
      puts "No node argument provided, defaulting to #{worker_one}"
      worker_one
    else
      ARGV.delete_at(0)
    end
  abort "Error: node '#{node_hostname}' not found" unless system("kubectl get node #{node_hostname} &> /dev/null")

  require "securerandom"

  # TODO: Move to reclaim-the-stack docker registry
  image = "mynewsdesk/utils:20230206-154225"
  exec %(
    kubectl run playground-#{SecureRandom.hex(3)} -it --restart=Never --rm --image #{image} \
    --overrides='
      {
        "apiVersion": "v1",
        "spec": {
          "nodeSelector": { "kubernetes.io/hostname": "#{node_hostname}" },
          "tolerations": [{ "operator": "Exists" }]
        }
      }
    ' -- bash
  )
end

def env_to_secret
  env_path = ARGV.delete_at(0)
  secret_name = ARGV.delete_at(0)
  unless env_path && secret_name
    puts "USAGE:"
    puts "First create a .env file, eg. from Heroku:"
    puts "heroku config -s -a <app> > app.env"
    puts ""
    puts "Now generate Kubernetes secrets / sealed secrets as desired:"
    puts "k env-to-secret app.env <secret-name> | kubeseal -o yaml > applications/shared-secrets/<secret-name>.yaml"
    exit
  end
  abort "Error: Could not locate an ENV file at '#{env_path}'" unless File.exist?(env_path)

  require "dotenv"
  require "psych"
  require "base64"

  data = Dotenv
    .load(env_path)
    .transform_values(&Base64.method(:strict_encode64))
    .sort
    .to_h

  secret = {
    "apiVersion" => "v1",
    "kind" => "Secret",
    "type" => "opaque",
    "data" => data,
    "metadata" => {
      "name" => secret_name,
    },
  }

  puts secret.to_yaml
end

def generate
  sub_command = ARGV.delete_at(0)

  if sub_command
    method = "generate_#{sub_command}"
    abort "Error: no generator named '#{sub_command}'" unless private_methods.include?(method.to_sym)
    send(method)
  else
    puts "Generator commands can help with creating Kubernetes resources and should be run from inside " \
         "your own clone of the devops-kubernetes repository."
    puts ""
    puts "GENERATORS:"
    # rubocop:disable Style/StringConcatenation
    puts "k generate application <application-name>" + gray(" generates a new application")
    puts "k generate deployment <application-name>" + gray(" generates a deployment for an application (web, sidekiq etc)")
    puts "k generate resource <application-name>" + gray(" generates a resource for an application (postgres, redis etc)")
    # rubocop:enable Style/StringConcatenation
  end
end

def generate_application
  application = ARGV.delete_at(0)
  abort "Must pass name of application to generate, eg. k generate application <application-name>" unless application
  abort "Error: Application name must only contain lower-case alphanumeric characters or '-'" unless application[/^[a-z-]+$/]

  directory = "applications/#{application}"

  abort "Error: An application named '#{application}' already exists" if File.exist?(directory)

  require "yaml"

  Dir.mkdir(directory)
  Dir.mkdir("#{directory}/templates")
  File.open("#{directory}/Chart.yaml", "w") do |file|
    chart = {
      "apiVersion" => "v2",
      "name" => application,
      "type" => "application",
      "version" => "1.0.0",
      "appVersion" => "1.0.0",
    }
    file.write chart.to_yaml.delete_prefix("---\n")
  end
  File.write("#{directory}/values.yaml", "")

  puts "Generated application skeleton:"
  puts "#{directory}/Chart.yaml"
  puts "#{directory}/values.yaml"
  puts "#{directory}/templates"
end

def generate_deployment
  application = ARGV.delete_at(0)
  abort "Must pass name of application, eg. k generate deployment <application>" unless application

  app_path = "applications/#{application}"
  abort "Error: no application found at '#{app_path}'" unless File.directory?(app_path)

  values_path = "#{app_path}/values.yaml"
  abort "Error: no helm values found at '#{values_path}'" unless File.exist?(values_path)

  puts "What type of deployment are you creating?"
  puts "1. Web"
  puts "2. Sidekiq"
  puts "3. Other"
  type =
    case readline.strip.downcase[0]
    when "1" then "web"
    when "2" then "sidekiq"
    when "3" then "other"
    else
      abort "Error: faulty input, must be a value from 1-3"
    end
  puts ""

  if type == "other"
    print "Please give the deployment a name: "
    name = readline.strip
    abort "Error: didn't provide a name" if name.empty?
    puts ""
  else
    name = type
  end

  if File.exist?("#{app_path}/templates/deployment-#{name}.yaml")
    print "A deployment named deployment-#{name} already exists for this application, please provide a suffix: "
    suffix = readline.strip.delete_prefix("-")

    abort "Error: didn't provide a suffix" if suffix.empty?

    name = "#{name}-#{suffix}"
    puts ""
  end

  abort "Error: deployment name must only contain lower-case alphanumeric characters or '-'" unless name[/^[a-z0-9-]+$/]
  if File.exist?("#{app_path}/templates/deployment-#{name}.yaml")
    abort "Error: there is already an existing deployment named '#{name}'"
  end

  default_image = "#{REGISTRY}/#{application}:sha-<git-sha>"

  camel_name = name.split("-").map.with_index { |word, i| i == 0 ? word : word.capitalize }.join
  deployment_template = format(
    File.read("templates/deployment-#{type}.yaml"),
    application: application,
    name: name,
    camelName: camel_name,
    image: default_image,
  )

  File.write("#{app_path}/templates/deployment-#{name}.yaml", deployment_template)
  puts "Created " + bold("#{app_path}/templates/#{name}.yaml") # rubocop:disable Style/StringConcatenation
  puts ""

  values_example = deployment_template
    .match(/# Example values\.yaml:\n([\s\S]*?)\n\n/)[1]
    .gsub(/^# /, "")

  if File.read(values_path).empty?
    File.write(values_path, values_example)
    puts "Injected examples values for the deployment into #{bold(values_path)}"
    puts "Please check out and modify the values.yaml to fit your use-case."
  else
    puts "Please modify and merge these example values into #{bold(values_path)}:"
    puts values_example
  end

  if type == "web"
    puts ""
    puts "To expose the deployment to the internet add an entry to the ingress section in:"
    puts bold("infrastructure/cloudflared/config-map.yaml")
    puts ""
    puts "Example:"
    # TODO: replace mynewsdesk.dev reference
    puts "- hostname: #{application}.mynewsdesk.dev"
    puts "  service: http://#{application}-web.default.svc:3000"
  end
end

def generate_resource
  application = ARGV.delete_at(0)
  abort "Must pass name of application, eg. k generate resource <application>" unless application

  app_path = "applications/#{application}"
  abort "Error: no application found at '#{app_path}'" unless File.directory?(app_path)

  values_path = "#{app_path}/values.yaml"
  abort "Error: no helm values found at '#{values_path}'" unless File.exist?(values_path)

  puts "What type of resource would you like to generate?"
  puts "1. Postgres"
  puts "2. Redis"
  puts "3. Elasticsearch"
  puts "4. Memcached"
  type =
    case readline.strip.downcase[0]
    when "1" then "postgres"
    when "2" then "redis"
    when "3" then "elasticsearch"
    when "4" then "memcached"
    else
      abort "Error: faulty input, must be a value from 1-4"
    end
  puts ""

  name = type

  if File.exist?("#{app_path}/templates/#{name}.yaml")
    print "A #{type} resource already exists for this application, please provide a suffix: "
    suffix = readline.strip.delete_prefix("-")

    abort "Error: didn't provide a suffix" if suffix.empty?

    suffix = "-#{suffix}"
    puts ""
  end

  name = "#{name}#{suffix}"

  abort "Error: name must only contain lower-case alphanumeric characters or '-'" unless name[/^[a-z0-9-]+$/]
  if File.exist?("#{app_path}/templates/#{name}.yaml")
    abort "Error: there is already an existing #{type} resource named '#{name}'"
  end

  camel_name = name.split("-").map.with_index { |word, i| i == 0 ? word : word.capitalize }.join
  resource_template = format(
    File.read("templates/#{type}.yaml"),
    application: application,
    name: name,
    camelName: camel_name,
    suffix: suffix,
  )

  File.write("#{app_path}/templates/#{name}.yaml", resource_template)
  puts "Created " + bold("#{app_path}/templates/#{name}.yaml") # rubocop:disable Style/StringConcatenation
  puts ""

  values_example = resource_template
    .match(/# Example values\.yaml:\n([\s\S]*?)\n\n/)[1]
    .gsub(/^# /, "")

  if File.read(values_path).empty?
    File.write(values_path, values_example)
    puts "Injected examples values for the deployment into #{bold(values_path)}"
    puts "Please check out and modify the values.yaml to fit your use-case."
  else
    puts "Please modify and merge these example values into #{bold(values_path)}:"
    puts values_example
  end
end

def redis_cli
  application = ARGV.delete_at(0)
  abort "Must pass name of application, eg. k redis-cli <application>" unless application

  require "yaml"

  endpoint_yaml = `kubectl get endpoints/#{application}-redis-master -o yaml`
  abort "Error: no master endpoint found for #{application} (looked for #{application}-redis-master)" if endpoint_yaml.empty?

  endpoint = YAML.safe_load(endpoint_yaml)
  master_pod = endpoint.dig("subsets", 0, "addresses", 0, "targetRef", "name")
  abort "Error: no master pod name found in endpoint YAML for #{application}-redis-master" unless master_pod

  puts "Running redis-cli on #{master_pod}..."
  system "kubectl exec -c redis -it #{master_pod} -- redis-cli"
end

# TODO: This should use sentinel failover instead of redis failover
def redis_failover
  application = ARGV.delete_at(0)
  abort "Must pass name of application, eg. k failover <application>" unless application

  require "yaml"

  endpoint_yaml = `kubectl get endpoints/#{application}-redis-master -o yaml`
  abort "Error: no master endpoint found for #{application} (looked for #{application}-redis-master)" if endpoint_yaml.empty?

  endpoint = YAML.safe_load(endpoint_yaml)
  master_pod = endpoint.dig("subsets", 0, "addresses", 0, "targetRef", "name")
  abort "Error: no master pod name found in endpoint YAML for #{application}-redis-master" unless master_pod

  puts "Running redis-cli with FAILOVER command on #{master_pod}..."
  system "kubectl exec -c redis -it #{master_pod} -- redis-cli FAILOVER"

  puts "Running redis-cli with CLIENT KILL TYPE normal on #{master_pod} for 30 seconds to evict existing connections..."
  30.times do
    system "kubectl exec -c redis -it #{master_pod} -- redis-cli CLIENT KILL TYPE normal"
    sleep 1
  end
end

PRIVATE_METHODS_AFTER_COMMANDS = private_methods - PRIVATE_METHODS_BEFORE_COMMANDS

def system_or_die(command)
  system(command) || abort("Unsuccessful exit code while running `#{command}`")
end

# If another process has pushed to the git repository while k was busy making changes git push will
# fail with "Updates were rejected because the remote contains work that you do not have locally."
# This method works around that by attempting to git pull and try again a few times before giving up.
def safe_git_push
  system("git config pull.rebase true")
  system("git pull --quiet")
  5.times do |i|
    return if system("git push #{'--quiet' if i == 0}") # rubocop:disable Lint/NonLocalExitFromIterator

    if i < 5
      puts "Failed to push changes, executing git pull before trying again"
      system("git pull")
    end
  end

  puts "Error: Failed to push changes to gitops repo, resetting git repository and aborting"
  system("git reset --hard origin/master")
  abort
end

# Private method returning an Array of Structs for the 15 latest releases to an application
def lookup_latest_releases(application)
  raise "must be in argocd repository while running #lookup_latest_releases" unless Dir.pwd == INTERNAL_REPO_PATH

  # https://git-scm.com/docs/pretty-formats
  git_log = `
    git log \
      -n 15 \
      --pretty=format:'%H<col>%aN<col>%ad<col>%ar<col>%s<col>%b<row>' \
      --follow -- applications/#{application}/values.yaml
  `

  release_struct = Struct.new(:sha, :pretty_sha, :author, :time, :relative_time, :subject, :body)

  git_log.split("<row>").map do |row|
    sha, author, time, relative_time, subject, body = row.strip.split("<col>")
    release_struct.new(
      sha: sha,
      pretty_sha: sha[0..10],
      author: author,
      time: Time.parse(time),
      relative_time: relative_time,
      subject: subject.delete_prefix("#{application}: "),
      body: body,
    )
  end
end

def dispatch(command)
  command = "_exec" if command == "exec"
  method = command.split(/[:-]/).join("_")

  send method
rescue NoMethodError => e
  # If the NoMethodError happened inside of the actual command we want to raise it
  raise unless e.name == method.to_sym

  did_you_mean = DidYouMean::SpellChecker.new(dictionary: PRIVATE_METHODS_AFTER_COMMANDS)
    .correct(method)
    .map { |suggestion| "'#{suggestion.to_s.split('_').join(':')}'" }
  puts "Error: no command called '#{command}'"
  puts ""
  puts "Perhaps you meant #{did_you_mean.join(' or ')}?" unless did_you_mean.empty?
  exit 1 # using 'abort' somehow automatically prints the Exception
end

command = ARGV.delete_at(0)

if command
  dispatch(command)
else
  print_commands
end
