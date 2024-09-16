#!/usr/bin/env ruby

# ENV variables of note:
# HOME - the user's home directory, we'll use this to store configuration and manage gitop repos under ~/.k
# KAIL_PATH - path to kail executable, defaults to "kail"
# KUBESEAL_PATH - path to kubeseal executable, defaults to "kubeseal"
# YQ_PATH - path to yq executable, defaults to "yq"

require "yaml"
require "tmpdir"
require "uri"

# rubocop:disable Style/StringConcatenation

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

if (K_CONTEXT = K_CONFIG["contexts"][K_CONFIG["context"]])
  ORGANIZATION = K_CONTEXT.fetch("github_organization").freeze
  GIT_HOST = URI(K_CONTEXT.fetch("repository")).host.freeze
  REPO_NAME = K_CONFIG["context"].freeze
  INTERNAL_REPO_PATH = "#{ENV.fetch('HOME')}/.k/#{REPO_NAME}".freeze
  REGISTRY = "#{K_CONTEXT.fetch('registry')}/#{K_CONTEXT.fetch('registry_namespace')}".freeze
  KUBECTL_CONTEXT = K_CONTEXT.fetch("kubectl_context").freeze
  abort("Fatal: couldn't locate gitops repository at #{INTERNAL_REPO_PATH}") unless File.directory?(INTERNAL_REPO_PATH)
elsif ARGV.first.to_s.start_with?("contexts")
  # Do nothing - we're about to add / list or use a context!
elsif K_CONFIG["contexts"].empty?
  puts "Warning: no contexts configured. Please run `k contexts:add <github/gitlab-repository>` to configure a context"
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

def kubectl(command)
  system "kubectl --context #{KUBECTL_CONTEXT} #{command}"
end

def read_kubectl(command)
  `kubectl --context #{KUBECTL_CONTEXT} #{command.strip}` # strip to allow leading newline
end

def kubeseal(source_path, destination_path)
  kubeseal_executable = ENV["KUBESEAL_PATH"] || "kubeseal"
  abort "Must have kubeseal installed" unless system "which #{kubeseal_executable} > /dev/null"

  system_or_die "#{kubeseal_executable} --context #{KUBECTL_CONTEXT} -f #{source_path} -o yaml > #{destination_path}"
end

def yq_executable
  executable = ENV["YQ_PATH"] || "yq"
  abort "Must have yq installed" unless system "which #{executable} > /dev/null"

  executable
end

def in_argo_repo
  # Prevent recursive git repo churn
  return yield if Thread.current[:in_argo_repo] == true

  Dir.chdir INTERNAL_REPO_PATH do
    Thread.current[:in_argo_repo] = true

    abort "Error: expected #{INTERNAL_REPO_PATH} to be a git repository" unless File.directory?(".git")

    status = `git status --porcelain`

    dirty = !!status.lines.find do |line|
      line.strip[/^[MDA]/] # dirty files are "M"odified, "D"eleted or "A"dded
    end

    abort "Error: your ArgoCD repository at #{INTERNAL_REPO_PATH} needs to be in a clean state to manipulate" if dirty

    system "git pull --rebase --quiet"

    result = yield

    Thread.current[:in_argo_repo] = false

    result
  end
end

def print_commands
  puts "COMMANDS:"
  puts "k applications [<application>]" + gray(" list applications or show application details")
  puts "k build-and-push" + gray(" build and push a docker image for an application")
  puts "k config <application> [<search-string>]" + gray(" list ENV vars for an application")
  puts "k config:edit <application>" + gray(" edit ENV vars on an application")
  puts "k config:get <application> <env-var>" + gray(" prints a single environment variable value for an application")
  puts "k contexts" + gray(" list available contexts")
  puts "k contexts:add <github/gitlab-repository>" + gray(" add a new context")
  puts "k contexts:use <context>" + gray(" switch to a different context")
  puts "k contexts:remove <context>" + gray(" remove a context")
  puts "k console <application>" + gray(" start a rails console on an application")
  puts "k cnpg" + gray(" shortcut for kubectl cnpg to manage CloudNativePG clusters")
  puts "k dashboard <application>" + gray(" opens application dashboard in grafana")
  puts "k deploy <application>" + gray(" deploy docker image to an application (run from repo/branch you want to deploy)")
  puts "k elasticsearch:url <cluster-name>" + gray(" output the internal URL for an elasticsearch cluster")
  puts "k env-to-secret <env-file> <secret-name>"
  puts "k generate" + gray(" list generate commands for creating / adding resources to applications")
  puts "k k <kubectl-arguments>" + gray(" run kubectl with the configured context applied")
  puts "k kibana <application>" + gray(" access kibana from an elastic search enabled application")
  puts "k logs <application> [<type1>, <type2>...]" + gray(" tail application logs")
  puts "k logs:search <application> [<regexp-query>]" + gray(" search application logs via grafana")
  puts "k pg" + gray(" list postgres related commands")
  puts "k redis:cli <cluster-name> [<arguments for redis-cli>]" + gray(" run redis-cli on redis for a redis cluster")
  puts "k redis:failover <cluster-name>" + gray(" run FAILOVER command on the current master instance")
  puts "k redis:url <cluster-name>" + gray(" output the internal URL for a redis cluster")
  puts "k redis:sentinel-url <cluster-name>" + gray(" output the internal sentinel URL for a redis cluster")
  puts "k releases <application>" + gray(" lists the past 15 releases for an application")
  puts "k restart <application>" + gray(" restart application deployments")
  puts "k rollback <application>" + gray(" show prompt to rollback an application")
  puts "k run <application> <command>" + gray(" run a command using a one off pod")
  puts "k secrets [<specific-secret>]" + gray(" lists secrets including usage details")
  puts "k secrets:create <secret-name>" + gray(" create a new secret")
  puts "k secrets:edit <secret-name>" + gray(" edit a secret")
  puts "k secrets:set <secret-name> <key>=<value> [<key2>=<value2> ...]" + gray(" set new secret values")
  puts "k secrets:unset <secret-name> <key> [<key2> ...]" + gray(" unset / delete secret values")
  puts "k update" + gray(" update k to the latest version")
  puts ""
  puts "DEBUGGING COMMANDS:"
  puts "k playground <node-name> [--privileged] [--host-network]" + gray(" open a utilities shell on a kubernetes node")
  puts "k sh <pod|deployment|statefulset>" + gray(" shell into a live deployment")
  puts "k exec <deployment> <command>" + gray(" execute a command on a live deployment")
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
      missing_applications = requested_applications - applications
      abort "Error: #{missing_applications.join(', ')} didn't match any applications" unless missing_applications.empty?

      requested_applications.each do |application|
        puts "#{gray('===')} #{bold(application)}"
        values = YAML.load_file("applications/#{application}/values.yaml")
        deployments = values["deployments"].to_h.map do |name, data|
          name_kebab = name.gsub(/(.)([A-Z])/, '\1-\2').downcase
          "#{name_kebab}: #{data.fetch('replicas')}"
        end
        puts ""
        puts "Deployments:"
        puts deployments
        puts ""
        resources = values["resources"].to_h.map { |name, data| "#{name}: #{data['replicas']}" }
        puts "Resources:"
        puts resources
      end
    end
  end
end

alias apps applications

def build_and_push
  abort "Error: you need to be in a git repository to use this command" unless File.exist?(".git")
  abort "Error: expected to be able to detect repository name via a git remote but non exist" unless system("git remote")

  git_remotes = `git remote`.split("\n")
  remote_to_use = git_remotes.include?("origin") ? "origin" : git_remotes.first

  repository = `git remote get-url #{remote_to_use}`.strip.split("/").last.delete_suffix(".git")
  git_sha = `git rev-parse HEAD`.chomp
  docker_repository = "#{REGISTRY}/#{repository}"
  target_image = "#{docker_repository}:sha-#{git_sha}"

  if ARGV.include?("help")
    puts bold "Description"
    puts "Builds and pushes a docker image for an application. By default it will use the "\
         "docker registry and namespace configured in the current k context, the repository name "\
         "as image name and the current git SHA as the tag."
    puts "For Dockerfile we will look for Dockerfile.k, Dockerfile.kubernetes and Dockerfile in "\
         "that order. This allows you to use a custom Dockerfile for kubernetes builds if so desired)."
    puts ""
    puts "In this case this would be:"
    puts target_image
    puts ""
    puts bold "Usage"
    puts "k build-and-push help" + gray(" displays this help message")
    puts "k build-and-push" + gray(" builds using Dockerfile and pushes to default image")
    exit
  end

  dockerfile =
    if File.exist?("Dockerfile.k")
      "Dockerfile.k"
    elsif File.exist?("Dockerfile.kubernetes")
      "Dockerfile.kubernetes"
    elsif File.exist?("Dockerfile")
      "Dockerfile"
    else
      abort "Error: no Dockerfile found in current directory"
    end

  build_args = []
  build_args << "--build-arg RUBY_VERSION=#{File.read('.ruby-version').chomp} \\" if File.exist?(".ruby-version")

  command = <<~BASH
    docker buildx build . \\
      -f #{dockerfile} \\
      #{build_args.join("\n")}
      --platform linux/amd64 \\
      -t #{docker_repository}:latest \\
      -t #{target_image} \\
      --cache-from type=registry,ref=#{docker_repository} \\
      --cache-to type=registry,ref=#{docker_repository} \\
      --progress plain \\
      --load
  BASH

  puts bold "Building with command"
  puts command
  system_or_die command
  puts ""

  command = "docker push #{target_image} && docker push #{docker_repository}:latest"
  puts bold "Pushing with command"
  puts command
  system_or_die command
end

def clickhouse_cli
  cluster = ARGV.delete_at(0)
  abort "Must pass name of cluster, eg. k clickhouse <cluster>" unless cluster

  pod = read_kubectl("get pods -l clickhouse.altinity.com/chi=#{cluster} -o name").lines.first&.strip
  abort "Error: no clickhouse pods found for cluster '#{cluster}'" unless pod

  kubectl "exec -it #{pod} -- clickhouse-client"
end

def contexts
  puts "#{gray('===')} #{bold('Contexts')}"
  puts ""

  longest_name = K_CONFIG.fetch("contexts").keys.max_by(&:length)
  longest_repo = K_CONFIG.fetch("contexts").values
    .map { |data| data.fetch("repository").split("/").last(2).join("/") }
    .max_by(&:length)

  offset_1 = longest_name.length + 2
  offset_2 = longest_repo.length + 2

  puts gray("Name".ljust(offset_1) + "Repository".ljust(offset_2) + "Kubernetes Context")
  current_context = K_CONFIG.fetch("context")
  K_CONFIG.fetch("contexts").each do |name, data|
    suffix = "  <-" if name == current_context
    repo = data.fetch("repository").split("/").last(2).join("/")
    puts name.ljust(offset_1) + repo.ljust(offset_2) + data.fetch("kubectl_context") + bold(suffix.to_s)
  end
end

def contexts_add
  repository_url = ARGV.delete_at(0)
  unless repository_url
    puts bold "Usage"
    puts "k contexts:add <github/gitlab-repository-url>"
    puts ""
    puts bold "Description"
    puts "Adds a k context. A context is a combination of:"
    puts "1. A GitHub/GitLab repository containing ArgoCD platform and applications manifests"
    puts "2. A Docker registry + namespace containing Docker images to be deployed as applications"
    puts "3. A Kubernetes cluster (ie. a locally configured kubectl context)"
    exit
  end

  require "fileutils"

  uri = URI(repository_url)
  abort "Error: URL must be a GitHub/GitLab repository" unless ['github.com', 'gitlab.com'].include?(uri.host)

  puts ""
  puts "Verifying access to #{repository_url}..."

  # Verify that we have read access to the repository
  tmp_repo_path = "/#{Dir.tmpdir}/k-context-add-#{Time.now.to_i}"
  unless system "git clone #{repository_url} -q #{tmp_repo_path}"
    abort "Error: could not clone repository #{repository_url}"
  end

  # Verify that we have write access to the repository
  write_access =
    Dir.chdir tmp_repo_path do
      test_branch_name = "write-access-test-#{Time.now.to_i}"
      system "git branch #{test_branch_name}"
      write_access = system "git push origin #{test_branch_name} -q &> /dev/null"

      # Wait for it to settle before deleting in order avoid an error like "error: unable to delete 'write-access-test-1707400094': remote ref does not exist"
      sleep 1

      system "git push -d origin #{test_branch_name} -q" if write_access
      write_access
    end
  FileUtils.rm_rf tmp_repo_path
  abort "Error: failed to verify write access to #{repository_url}" unless write_access

  puts "Write access verified ✅"
  puts ""

  github_organization, repository_name = uri.path.delete_prefix("/").split("/")
  repository_name = repository_name.delete_suffix(".git")

  default_context_name = repository_name
  print "What would you like to name this context? [#{default_context_name}] "
  context_name = readline.strip
  context_name = default_context_name if context_name.empty?

  if K_CONFIG.fetch("contexts").key?(context_name)
    puts "A context named '#{context_name}' already exists"
    print "What would you like to name it instead?"
    context_name = readline.strip
  end

  abort "Error: context name cannot be blank" if context_name.empty?
  abort "Error: context can only contain alphanumerics, dashes, and underscores" unless context_name =~ /^[a-zA-Z0-9_-]+$/
  abort "Error: context name '#{context_name}' already exists" if K_CONFIG.fetch("contexts").key?(context_name)
  puts ""

  default_registry = "docker.io"
  print "Which Docker registry should be used for this context? [#{default_registry}] "
  registry = readline.strip
  registry = default_registry if registry.empty?

  print "Which Docker registry namespace should be used for this context? [#{github_organization}] "
  registry_namespace = readline.strip
  registry_namespace = github_organization if registry_namespace.empty?
  puts ""

  # NOTE: Docker authentication is only required when pushing images form the local machine
  # but best practice is to use an external CI/CD. So we've retired verifying access to the
  # specified registry.
  #
  # We could consider adding it back in the future but then we'd need to figure out a better
  # test than using `docker login` since that prompots the user for a user/password unless
  # already logged in.

  # puts "Verifying access to registry..."
  # registry_host = registry.split("/").first
  # abort "Error: failed to verify access to #{registry}" unless system "docker login #{registry_host} > /dev/null"
  # puts "Access to #{registry_host} verified ✅"
  # puts "NOTE: write access to the #{registry}/#{registry_namespace} namespace is assumed but not verified"
  # puts ""

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

def contexts_remove
  context_name = ARGV.delete_at(0)
  abort "Must pass name of context to remove, eg. k contexts:remove <context>" unless context_name

  abort "Error: context '#{context_name}' does not exist" unless K_CONFIG.fetch("contexts").key?(context_name)

  require "fileutils"

  FileUtils.rm_rf "#{ENV.fetch('HOME')}/.k/#{context_name}"
  K_CONFIG["context"] = nil if K_CONFIG["context"] == context_name
  K_CONFIG.fetch("contexts").delete(context_name)
  File.write(K_CONFIG_FILE, K_CONFIG.to_yaml)

  puts ""
  puts "Context '#{context_name}' was removed 🗑"
  unless K_CONFIG["context"]
    puts ""
    puts "Warning: You now have no active context, run `k contexts:set <context>` to set one"
  end
end

def contexts_use
  context_name = ARGV.delete_at(0)
  abort "Must pass name of context, eg. k contexts:use <context>" unless context_name

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

  require "socket"

  5601.upto(5700) do |port|
    # If we can connect to the port another kibana is already active and we skip to the next port
    next if TCPSocket.new("127.0.0.1", port).close.nil? rescue false # rubocop:disable Style/RescueModifier

    puts "Making kibana accessible at: http://localhost:#{port}/app/monitoring#/overview"
    if system "which pbcopy > /dev/null 2>&1"
      puts "Storing kibana password in clipboard..."
      puts ""
      kubectl "get secret #{application}-es-elastic-user --template={{.data.elastic}} | base64 -d | pbcopy"
      puts "Login with username 'elastic' and paste the password from your clipboard"
    else
      require "base64"
      base64_password = read_kubectl "get secret #{application}-es-elastic-user --template={{.data.elastic}}"
      password = Base64.decode64(base64_password)
      puts "Login with username 'elastic' and paste the password '#{password}'"
    end
    puts ""
    kubectl "port-forward service/#{application}-kb-http #{port}:5601"
  end
end

# NOTE: not ready for use and we might not need this
def config_set
  abort "Error: config:set has not been implemented, please use config:edit / secrets:edit instead"

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

def cnpg
  system "kubectl cnpg --context #{KUBECTL_CONTEXT} #{ARGV.join(" ")}"
end

def dashboard
  application = ARGV.delete_at(0)
  abort "Must pass name of application, eg. k dashboard <application>" unless application

  grafana_query = URI.encode_www_form(
    {
      "orgId" => "1",
      "from" => "now-1h",
      "to" => "now",
      "var-namespace" => "default",
      "var-deployment" => "#{application}-web",
    },
  )

  domain = detect_deploy_domain("grafana")
  grafana_url = "https://grafana.#{domain}/d/application/application?#{grafana_query}"

  puts "Opening #{grafana_url} ..."
  system "open \"#{grafana_url}\""
end

def k
  if ARGV.empty?
    puts "DESCRIPTION:"
    puts "The k command runs kubectl with the current k context applied"
    puts ""
    puts "EXAMPLE:"
    puts "k k get pods"
  else
    kubectl(ARGV.join(" "))
  end
end

def logs
  application = ARGV.delete_at(0)
  abort "Must pass name of application, eg. k logs <application> [<type1>, <type2>...]" unless application

  kail_executable = ENV["KAIL_PATH"] || "kail"
  abort "Please install kail (brew install kail) for logs support" unless system("which #{kail_executable} > /dev/null")

  require "json"

  deployments_json = read_kubectl "get deployments -o json -l argocd.argoproj.io/instance=#{application}"
  deployments = JSON.parse(deployments_json).fetch("items")
  abort "Couldn't find any deployments for the application #{application}" if deployments.empty?

  deployment_names = deployments.map { |deployment| deployment.fetch("metadata").fetch("name") }
  unless ARGV.empty?
    deployment_names.select! { |deployment| ARGV.include? deployment.delete_prefix("#{application}-") }
    abort "couldn't find any deployments matching #{ARGV.join(', ')}" if deployment_names.empty?
  end

  kail_arguments = deployment_names.map { |name| "-d #{name}" }.join(" ")

  puts "Tailing logs from #{deployment_names.join(', ')}..."
  exec "#{kail_executable} --context #{KUBECTL_CONTEXT} #{kail_arguments}"
end

def logs_search
  application = ARGV.delete_at(0)
  abort "Must pass name of application, eg. k logs:search <application> [<type1>, <type2>...]" unless application

  require "json"

  deployments_json = read_kubectl "get deployments -o json -l argocd.argoproj.io/instance=#{application}"
  deployments = JSON.parse(deployments_json).fetch("items")
  abort "Couldn't find any deployments for the application #{application}" if deployments.empty?

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
  domain = detect_deploy_domain("grafana")
  grafana_url = "https://grafana.#{domain}/explore?left=#{grafana_query}"

  puts "Opening #{grafana_url} ..."
  system "open #{grafana_url}"
end

module Pg
  def self.secret_for_cluster(cluster_name, user = nil)
    require "json"

    # Prefer cloudnativepg cluster if available
    return cloudnative_secret_for_cluster(cluster_name, user) unless read_kubectl("get cluster #{cluster_name} -o json --ignore-not-found").empty?

    cluster = read_kubectl("get postgrescluster #{cluster_name} -o json --ignore-not-found")

    abort "Error: postgrescluster '#{cluster_name}' not found" if cluster.empty?

    cluster = JSON.parse(cluster)
    user ||= cluster.dig("spec", "users", 0, "name")
    unless user
      puts "No users found in PostgresCluster spec, using default user '#{cluster_name}'"
      user = cluster_name
    end

    secret = read_kubectl("get secret #{cluster_name}-pguser-#{user} -o json")

    abort "ERROR: Could not find user '#{user}' in cluster '#{cluster_name}'" if secret.empty?

    JSON.parse(secret).fetch("data")
  end

  def self.cloudnative_secret_for_cluster(cluster_name, user = nil)
    unless user.nil? || user == "superuser"
      abort "ERROR: CloudNativePG clusters only support default (ie. do not specify) or superuser users"
    end

    require "json"
    require "base64"

    cluster = read_kubectl("get cluster #{cluster_name} -o json")
    abort "Error: cluster '#{cluster_name}' not found" if cluster.empty?

    cluster = JSON.parse(cluster)
    user ||= cluster_name

    app_secret = read_kubectl("get secret #{cluster_name}-app -o json")
    abort "ERROR: Could not find authentication secret for '#{cluster_name}'" if app_secret.empty?
    app_secret = JSON.parse(app_secret).fetch("data")

    if user == "superuser"
      superuser_secret = read_kubectl("get secret #{cluster_name}-superuser -o json")
      abort "ERROR: Could not find superuser secret for '#{cluster_name}'" if superuser_secret.empty?
      superuser_secret = JSON.parse(superuser_secret).fetch("data")

      # Superuser secrets use * as dbname since they can theoretically connect to any database,
      # however this doesn't provide valid URL's to successfully connect via psql.
      uri = Base64.strict_decode64(superuser_secret.fetch("uri")).delete_suffix("*") + Base64.strict_decode64(app_secret.fetch("dbname"))
      superuser_secret.merge(
        "dbname" => app_secret.fetch("dbname"),
        "uri" => Base64.strict_encode64(uri),
      )
    else
      app_secret
    end
  end

  def self.exec_on_primary(cluster, command)
    container = "postgres"
    primary_pod_name = read_kubectl("get pod --selector=cnpg.io/instanceRole=primary,cnpg.io/cluster=#{cluster} -o name").chomp

    # Fallback on PGO cluster
    if primary_pod_name.empty?
      primary_pod_name = read_kubectl("get pod --selector=postgres-operator.crunchydata.com/role=master,postgres-operator.crunchydata.com/cluster=#{cluster} -o name").chomp
      container = "database"
    end

    abort "Error: no primary pod found for cluster '#{cluster}' to run command on" if primary_pod_name.empty?

    kubectl "exec #{primary_pod_name} -it -c #{container} -- #{command}"
  end

  def self.query_on_primary(cluster, query)
    secret = secret_for_cluster(cluster)

    require "base64"

    uri = Base64.strict_decode64(secret.fetch("uri"))
    exec_on_primary cluster, %(psql '#{uri}' -c "#{query}")
  end
end

def pg
  puts "Note: <cluster-name> is the same as <application-name> when following standard naming conventions."
  puts ""
  puts "POSTGRES COMMANDS:"
  puts "pg:failover <cluster-name>"
  puts "pg:patroni <cluster-name> <patroni-command>"
  puts "pg:password <cluster-name> [<username>]"
  puts "pg:pods"
  puts "pg:primaries"
  puts "pg:proxy" + gray(" connect to any Kubernetes Postgres instance via localhost")
  puts "pg:psql <cluster-name>"
  puts "pg:resources <cluster-name>"
  puts "pg:url <cluster-name>"
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

  kubectl %(annotate postgrescluster #{cluster} --overwrite postgres-operator.crunchydata.com/trigger-switchover="$(date)")
end

def pg_patroni
  cluster = ARGV.delete_at(0)
  abort "Must pass name of cluster, eg. k pg:patroni <cluster-name> <command>" unless cluster

  patroni_command = ARGV.delete_at(0) || "--help"

  Pg.exec_on_primary(cluster, "patronictl #{patroni_command}")
end

def pg_password
  cluster = ARGV.delete_at(0)
  abort "Must pass name of cluster, eg. k pg:password <cluster-name> [<user>]" unless cluster

  user = ARGV.delete_at(0)

  require "json"
  require "base64"

  secret = Pg.secret_for_cluster(cluster, user)
  password = Base64.strict_decode64(secret.fetch("password"))

  puts password
end

def pg_pods
  puts bold("PGO")
  kubectl "get pods -o wide --selector=postgres-operator.crunchydata.com/data=postgres"
  puts "", bold("CloudNativePG")
  kubectl "get pods -o wide --selector=cnpg.io/podRole=instance"
end

def pg_primaries
  puts bold("PGO")
  kubectl "get pods -o wide --selector=postgres-operator.crunchydata.com/role=master"
  puts "", bold("CloudNativePG")
  kubectl "get pods -o wide --selector=cnpg.io/instanceRole=primary"
end

def pg_proxy
  exec "#{__dir__}/k_pg_proxy #{KUBECTL_CONTEXT}"
end

def pg_psql
  cluster_name = ARGV.delete_at(0)
  abort "Must pass name of cluster, eg. k pg:psql <cluster-name> [<user>]" unless cluster_name

  user = ARGV.delete_at(0)

  secret = Pg.secret_for_cluster(cluster_name, user)

  require "base64"

  use_pg_bouncer = secret.key?("pgbouncer-uri")
  uri = Base64.strict_decode64(secret.fetch(use_pg_bouncer ? "pgbouncer-uri" : "uri"))
  puts "Connecting via PgBouncer..." if use_pg_bouncer

  Pg.exec_on_primary(cluster_name, "env PSQL_HISTORY=/dev/null psql '#{uri}'")
end

def pg_resources
  cluster = ARGV.delete_at(0)
  abort "Must pass name of cluster, eg. k pg:resources <cluster-name>" unless cluster

  puts bold("PGO")
  kubectl "get all --selector=postgres-operator.crunchydata.com/cluster=#{cluster}"
  puts ""
  kubectl "get secrets --selector=postgres-operator.crunchydata.com/cluster=#{cluster}"
  puts "", bold("CloudNativePG")
  kubectl "get all --selector=cnpg.io/cluster=#{cluster}"
  puts ""
  kubectl "get secrets --selector=cnpg.io/cluster=#{cluster}"
end

def pg_url
  cluster_name = ARGV.delete_at(0)
  abort "Must pass name of cluster, eg. k pg:url <cluster-name> [<user>]" unless cluster_name

  user = ARGV.delete_at(0)
  secret = Pg.secret_for_cluster(cluster_name, user)

  require "base64"

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
  disable_timeout = ARGV.delete("--disable-timeout")

  abort "Must pass name of application, eg. k run <application> <command> [--disable-timeout]" unless application
  abort "Must pass command to run, eg. k run <application> <command> [--disable-timeout]" if ARGV.empty?

  require "json"

  deployments_json = read_kubectl "get deployments -o json -l argocd.argoproj.io/instance=#{application}"
  deployments = JSON.parse(deployments_json).fetch("items")
  abort "Couldn't find any deployments for the application #{application}" if deployments.empty?

  require "securerandom"

  deployment =
    deployments.find { |d| d.fetch("metadata").fetch("name").end_with?("-web") } ||
    deployments.first
  pod_spec = deployment.fetch("spec").fetch("template").fetch("spec")
  default_container = deployment.dig("spec", "template", "metadata", "annotations", "kubectl.kubernetes.io/default-container")
  run_container =
    if default_container
      pod_spec.fetch("containers").find { |c| c.fetch("name") == default_container } or abort "Error: The deployment did not include a container named #{default_container}"
    else
      pod_spec.fetch("containers").first
    end
  other_containers = pod_spec.fetch("containers") - [run_container]

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
      containers: other_containers + [
        {
          name: "run",
          image: run_container.fetch("image"),
          envFrom: run_container["envFrom"] || [],
          env: run_container["env"] || [],
          imagePullPolicy: "IfNotPresent",
          command: ["sleep", disable_timeout ? "86400" : "3600"], # shutdown the pod after 1 hour or 24 hours
        },
      ],
    },
  }

  puts "Creating pod #{pod_name}..."
  system("echo '#{pod_template.to_json}' | kubectl --context #{KUBECTL_CONTEXT} apply -f -") || abort("failed to create pod")

  unless kubectl("wait pod #{pod_name} --for=condition=ContainersReady --timeout=120s > /dev/null")
    puts "failed to start pod, attempting to delete it..."
    kubectl "delete pod #{pod_name} --wait=false"
    abort
  end

  command = ARGV.join(" ")
  puts "Running #{command} on #{pod_name}..."
  command_success = kubectl "exec #{pod_name} -c run -it -- sh -c '#{command}'"
  kubectl("delete pod #{pod_name} --wait=false") || abort("failed to delete the pod")
  abort unless command_success
end

def console
  application = ARGV.delete_at(0)
  abort "Must pass name of application, eg. k console <application>" unless application

  system %(#{__dir__}/k run #{application} "EAGER_LOAD=false IRB_USE_AUTOCOMPLETE=true bundle exec rails console")
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

    values = YAML.load_file(values_path)

    env = {}

    shared_secrets = (values["envFrom"] || []).map { |config| config.fetch("secretRef").fetch("name") }
    shared_secrets.each do |secret_name|
      secret = YAML.safe_load read_kubectl("get secret #{secret_name} -o yaml")
      secret_env = secret.fetch("data").transform_values do |value|
        { value: Base64.strict_decode64(value), source: secret_name }
      end
      env.merge!(secret_env)
    end

    Array(values["env"]).each do |env_entry|
      name = env_entry.fetch("name")
      if (value = env_entry["value"])
        env[name] = { value: value, source: "values.yaml" }
      elsif (value_from = env_entry["valueFrom"])
        if (secret_ref = value_from["secretKeyRef"])
          secret_name = secret_ref.fetch("name")
          secret_key = secret_ref.fetch("key")
          secret = YAML.safe_load read_kubectl("get secret #{secret_name} -o yaml")
          value = Base64.strict_decode64(secret.fetch("data").fetch(secret_key))
          env[name] = { value: value, source: "values.yaml ref: #{secret_name}.#{secret_key}" }
        else
          raise "not sure how to parse env entry in #{values_path}: #{env_entry}"
        end
      else
        raise "not sure how to parse env entry in #{values_path}: #{env_entry}"
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

    Hash(values["deployments"]).each do |deployment_name, deployment|
      deployment_env = Array deployment["env"]
      next if deployment_env.empty?

      deployment_env.sort_by! { |entry| entry.fetch("name") }
      output = deployment_env.map do |entry|
        name = entry.fetch("name")
        value = entry["value"] || entry["valueFrom"]
        "#{green(name)}: #{value.to_yaml.delete_prefix('--- ').chomp} #{gray('# values.yaml')}"
      end

      output = output.grep(Regexp.new(grep_string)) if grep_string
      next if output.empty?

      puts ""
      puts "#{deployment_name.capitalize} deployment overrides:"
      puts output
    end
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
      puts "To edit #{application} environment via values.yaml please manually edit https://#{GIT_HOST}/#{ORGANIZATION}/#{REPO_NAME}/blob/master/applications/#{application}/values.yaml and open a Pull Request for review." # rubocop:disable Layout/LineLength
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

    values = YAML.load_file(values_path)

    env = {}

    shared_secrets = (values["envFrom"] || []).map { |config| config.fetch("secretRef").fetch("name") }
    shared_secrets.each do |secret_name|
      secret = YAML.safe_load read_kubectl("get secret #{secret_name} -o yaml")
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
            secret = YAML.safe_load read_kubectl("get secret #{secret_name} -o yaml")
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
  if ARGV.empty?
    puts "DESCRIPTION:"
    puts "The k deploy command deploys a Docker image to an application in Kubernetes by modifying the image attribute in the applications values.yaml file. Should be run from the application git repository. If no explicit git-sha is provided, the current git-sha of the current working directory is used. By default the command will verify that the image exists in the docker registry before proceeding, this doesn't appear to work with all docker registries and can be disabled with the --disable-image-verification flag." # rubocop:disable Layout/LineLength
    puts ""
    puts "USAGE:"
    puts "k deploy <application> [<git-sha>] [--enable-image-verification]"
    puts ""
    puts "EXAMPLE:"
    puts "k deploy <application>" + gray(" deploys the current <git-sha> of the current working directory to <application>")
    puts "k deploy <application> <git-sha>" + gray(" deploys an image with the given <git-sha> to <application>")
    puts "k deploy <application> --enable-image-verification" + gray(" tries to verify that the docker image exist before deploying")
    exit
  end

  ARGV.delete("--disable-image-verification") # deprecated option
  enable_image_verification = ARGV.delete("--enable-image-verification")
  application = ARGV.delete_at(0)

  git_sha = ARGV.delete_at(0) || `git rev-parse HEAD`.chomp
  abort "Error: couldn't fetch git-sha from current working dir, not in a git directory?" if git_sha.empty?

  commit_author = `git log -1 --pretty=%an`.chomp
  commit_email = `git log -1 --pretty=%ae`.chomp
  commit_subject = `git log -1 --pretty=%s`.chomp

  if commit_author.empty? || commit_email.empty? || commit_subject.empty?
    abort "Error: couldn't fetch git commit meta-data, not in a git directory?"
  end

  in_argo_repo do
    chart_yaml_path = "applications/#{application}/Chart.yaml"
    abort "Error: couldn't find app chart at #{INTERNAL_REPO_PATH}/#{chart_yaml_path}" unless File.exist?(chart_yaml_path)

    values_yaml_path = "applications/#{application}/values.yaml"
    abort "Error: couldn't find app configuration at #{INTERNAL_REPO_PATH}/#{values_yaml_path}" unless File.exist?(values_yaml_path)

    # eg. europe-north1-docker.pkg.dev/kubernetes-367912/mynewsdesk/mynewsdesk:sha-31e762a6c69881d4df792ab64da3c8cb58842cdb
    image = `#{yq_executable} .image #{values_yaml_path}`.chomp
    image_prefix = image.split(":").first
    new_image = "#{image_prefix}:sha-#{git_sha}"

    if enable_image_verification
      puts "Verifying existence of image: #{new_image}"
      # TODO: manifest inspect is unreliable, we could try using the registry API instead
      # eg. curl -I https://hub.docker.com/v2/repositories/reclaimthestack/rails-example/tags/latest
      # curl -s -H "Content-Type: application/json" -X POST -d '{"username": "reclaimthestack", "password": "..."}' https://hub.docker.com/v2/users/login/ | jq .token
      # curl -I -H "Authorization: Bearer <token>" https://hub.docker.com/v2/repositories/reclaimthestack/private-test/tags/latest
      1.upto(60) do |second|
        # NOTE: we have seen docker manifest inspect fail randomly even when the image exists, possibly a bug in the registry
        break if system "docker manifest inspect #{new_image} > /dev/null"

        abort "Error: Timed out waiting for #{new_image}, maybe something's wrong with the docker build?" if second == 60

        print "."
        sleep 1
      end
    end

    puts "--- Updating Helm chart image and app version"

    system_or_die %(#{yq_executable} -i ".appVersion = \\"#{git_sha}\\"" #{chart_yaml_path})
    system_or_die %(#{yq_executable} -i ".image = \\"#{new_image}\\"" #{values_yaml_path})

    puts "--- Pushing changes to gitops repo"

    status = `git status --porcelain`
    clean = !status.lines.find do |line|
      line.strip[/^[MDA]/] # dirty files are "M"odified, "D"eleted or "A"dded
    end
    if clean
      puts "Your branch is up to date with 'origin/master'. It appears this revision is already deployed."
      exit
    end

    repository = image.split("/").last.split(":").first
    system_or_die %(git commit --author="#{commit_author} <#{commit_email}>" -a -F - <<EOF

#{application}: Deploy "#{commit_subject}"

GitHub link: https://#{GIT_HOST}/#{ORGANIZATION}/#{repository}/commit/#{git_sha}
EOF)

    safe_git_push

    puts "+++ Tracking deployment progress"

    puts "Waiting for ArgoCD to deploy the new image:"
    puts new_image

    # NOTE: This assumes that the application is using deployments or cron_jobs to run the image
    # If some other resource type is used, this will time out.
    1.upto(120) do |second|
      deployments = read_kubectl %(
        get deployments \
        -l argocd.argoproj.io/instance=#{application} \
        -o=jsonpath="{.items[*].spec.template.spec.containers[*].image}"
      )
      break if deployments.include?(new_image)

      cron_jobs = read_kubectl %(
        get cronjobs \
        -l argocd.argoproj.io/instance=#{application} \
        -o=jsonpath="{.items[*].spec.jobTemplate.spec.template.spec.containers[*].image}"
      )
      break if cron_jobs.include?(new_image)

      abort "Error: Timed out waiting for new image deployment" if second == 120

      sleep 1
    end
  end
end

def elasticsearch_url
  elasticsearch_cluster = ARGV.delete_at(0)
  abort "Must pass name of elasticsearch cluster, eg. k elasticsearch:url <cluster-name>" unless elasticsearch_cluster

  require "json"
  require "base64"

  secret = read_kubectl("get secret #{elasticsearch_cluster}-es-elastic-user -o json")
  password = JSON.parse(secret).fetch("data").fetch("elastic")
  decoded_password = Base64.strict_decode64(password)

  puts "http://elastic:#{decoded_password}@#{elasticsearch_cluster}-es-http:9200"
end

# NOTE: Not ready for use yet, we'll encourage manual editing of values.yaml for now
def env_edit
  application = ARGV.delete_at(0)
  abort "Must pass name of application, eg. k edit-env <application>" unless application
  abort "Missing $EDITOR environment variable, eg: export EDITOR='code --wait --new-window'" unless ENV.key?("EDITOR")

  in_argo_repo do
    values_yaml_path = "applications/#{application}/values.yaml"
    abort "Error: couldn't find app configuration at #{INTERNAL_REPO_PATH}/#{values_yaml_path}" unless File.exist?(values_yaml_path)

    values = YAML.load_file(values_yaml_path)
    original_env = values.slice("envFrom", "env")

    # Write temporary file and launch editor
    tmp_file = "/#{Dir.tmpdir}/#{application}.yaml"
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
    abort "Error: No releases found for #{application}" if releases.empty?

    longest_subject = releases.map(&:subject).max_by(&:length)

    puts gray("=== ") + bold(application) + bold(" Releases")
    puts ""
    puts gray("Version".ljust(13) + "Time".ljust(21) + "Subject".ljust(longest_subject.length + 2) + "Author")
    today = Time.now.strftime("%Y-%m-%d")
    releases.each do |release|
      time_to_show =
        if release.time.strftime("%Y-%m-%d") == today
          "today at #{release.time.strftime('%H:%M:%S')}".ljust(19)
        else
          release.time.strftime("%Y-%m-%d %H:%M:%S")
        end
      puts "#{bold(release.pretty_sha)}  #{green(time_to_show)}  #{release.subject.ljust(longest_subject.length)}  #{cyan(release.author)}"
    end
  end
end

def rollback
  application = ARGV.delete_at(0)
  abort "Must pass name of application, eg. k rollback <application>" unless application

  require "time"

  in_argo_repo do
    releases = lookup_latest_releases(application)
    longest_subject = releases.map(&:subject).max_by(&:length)

    puts gray("=== ") + bold(application) + bold(" Rollback")
    puts ""
    puts gray("    Version".ljust(17) + "Time".ljust(21) + "Subject".ljust(longest_subject.length + 2) + "Author")
    today = Time.now.strftime("%Y-%m-%d")
    releases.each.with_index do |release, index|
      adjusted_index = "#{index}.".ljust(3)
      version = index == 0 ? "    #{release.pretty_sha}".ljust(15) : "#{bold(adjusted_index)} #{release.pretty_sha}"
      time_to_show =
        if release.time.strftime("%Y-%m-%d") == today
          "today at #{release.time.strftime('%H:%M:%S')}".ljust(19)
        else
          release.time.strftime("%Y-%m-%d %H:%M:%S")
        end
      puts "#{version}  #{green(time_to_show)}  #{release.subject.ljust(longest_subject.length)}  #{cyan(release.author)}"
    end
    puts ""

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

    domain = detect_deploy_domain("argocd")
    puts "Follow progress at: https://argocd.#{domain}/applications/argocd/#{application}?resource=health%3AProgressing"
  end
end

def secrets
  specific_secret = ARGV.delete_at(0)

  in_argo_repo do
    application_secrets = Dir.glob("applications/*/values.yaml").each_with_object({}) do |path, hash|
      application = path.split("/")[1]
      YAML.load_file(path)["envFrom"]&.each do |entry|
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
    require "base64"

    original_secret = YAML.safe_load read_kubectl("get secret #{shared_secret} -o yaml")
    original_env = original_secret.fetch("data").transform_values(&Base64.method(:strict_decode64))

    # Write temporary file and launch editor
    tmp_file = "/#{Dir.tmpdir}/#{shared_secret}.yaml"
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
    kubeseal tmp_file, "applications/shared-secrets/#{shared_secret}.yaml"
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

def secrets_set
  if ARGV.length < 2
    puts "Usage: k secrets:set <secret-name> <key>=<value> [<key2>=<value2> ...]"
    exit
  end

  shared_secret = ARGV.delete_at(0)
  new_env = ARGV.map { |argument| argument.split("=", 2) }

  abort "Error: all environment variables must be in the form <key>=<value>" if new_env.any? { _1.length != 2 }

  new_env = new_env.to_h

  bad_keys = new_env.keys.grep_v(/^[A-Z_][A-Z0-9_]*$/)
  abort "Error: invalid environment variable names: #{bad_keys.join(', ')}" unless bad_keys.empty?

  in_argo_repo do
    secret_path = "applications/shared-secrets/#{shared_secret}.yaml"
    abort "No shared secret found at '#{secret_path}'" unless File.exist?(secret_path)

    require "base64"

    original_secret = YAML.safe_load read_kubectl("get secret #{shared_secret} -o yaml")
    original_env = original_secret.fetch("data").transform_values(&Base64.method(:strict_decode64))

    new_env = original_env.merge(new_env)

    if new_env == original_env
      puts "No changes detected, skipping..."
      exit
    end

    data = new_env.transform_values(&:to_s).transform_values(&Base64.method(:strict_encode64))
    original_secret["data"] = data

    tmp_file = "/#{Dir.tmpdir}/#{shared_secret}.yaml"
    File.write(tmp_file, original_secret.to_yaml)
    kubeseal tmp_file, secret_path
    File.delete tmp_file

    changed_variables = new_env.keys.select do |name|
      original_env[name] && original_env[name] != new_env[name]
    end
    added_variables = new_env.keys - original_env.keys

    commit_message = "shared-secrets: edited #{shared_secret}\n\n"
    commit_message << "Changed: #{changed_variables.join(' ')}\n" unless changed_variables.empty?
    commit_message << "Added: #{added_variables.join(' ')}\n" unless added_variables.empty?

    puts commit_message

    system %(git commit -a -m "#{commit_message}" --quiet)
    safe_git_push
  end
end

def secrets_unset
  if ARGV.length < 2
    puts "Usage: k secrets:unset <secret-name> <key1> [<key2> ...]"
    exit
  end

  shared_secret = ARGV.delete_at(0)

  in_argo_repo do
    secret_path = "applications/shared-secrets/#{shared_secret}.yaml"
    abort "No shared secret found at '#{secret_path}'" unless File.exist?(secret_path)

    require "base64"

    original_secret = YAML.safe_load read_kubectl("get secret #{shared_secret} -o yaml")
    original_env = original_secret.fetch("data").transform_values(&Base64.method(:strict_decode64))

    new_env = original_env.except(*ARGV)

    if new_env == original_env
      puts "No changes detected, skipping..."
      exit
    end

    data = new_env.transform_values(&:to_s).transform_values(&Base64.method(:strict_encode64))
    original_secret["data"] = data

    tmp_file = "/#{Dir.tmpdir}/#{shared_secret}.yaml"
    File.write(tmp_file, original_secret.to_yaml)
    kubeseal tmp_file, secret_path
    File.delete tmp_file

    deleted_variables = original_env.keys - new_env.keys

    commit_message = "shared-secrets: edited #{shared_secret}\n\n"
    commit_message << "Deleted: #{deleted_variables.join(' ')}\n"

    puts commit_message

    system %(git commit -a -m "#{commit_message}" --quiet)
    safe_git_push
  end
end

def secrets_create
  secret = ARGV.delete_at(0)
  abort "Must pass name of the new secret, eg. k secrets:create <secret-name>" unless secret
  abort "Missing $EDITOR environment variable, eg: export EDITOR='code --wait --new-window'" unless ENV.key?("EDITOR")

  require "base64"

  in_argo_repo do
    secret_path = "applications/shared-secrets/#{secret}.yaml"
    if File.exist?(secret_path)
      abort "Error: A secret named '#{secret}' already exists, run 'k secrets:edit #{secret}' to edit it"
    end

    tmp_file = "/#{Dir.tmpdir}/#{secret}.yaml"
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
    kubeseal tmp_file, secret_path
    File.delete tmp_file

    system_or_die "git add #{secret_path}"
    system_or_die %(git commit -m "shared-secrets: add #{secret}" --quiet)
    safe_git_push

    puts "Successfully created the secret '#{secret}'"
  end
end

def sh
  resource = ARGV.delete_at(0)
  abort "Must pass name of a deployment, statefulset or pod, eg. k sh <deployment|statefulset|pod>" unless resource

  resource_type =
    if kubectl("get pods/#{resource} &> /dev/null")
      "pods"
    elsif kubectl("get deployments/#{resource} &> /dev/null")
      "deployments"
    elsif kubectl("get statefulsets/#{resource} &> /dev/null")
      "statefulsets"
    else
      abort "Error: '#{resource_type}' not found among pods, deployments or statefulsets"
    end

  command = "sh -c 'which bash > /dev/null && bash || sh'"
  exec "kubectl exec --context #{KUBECTL_CONTEXT} -it #{resource_type}/#{resource} -- #{command}"
end

def _exec
  deployment = ARGV.delete_at(0)
  abort "Must pass name of deployment, eg. k exec <deployment>" unless deployment
  abort "Must pass a command to run, eg. k exec <deployment> <command>" if ARGV.empty?

  exec "kubectl exec  --context #{KUBECTL_CONTEXT} -it deployments/#{deployment} -- #{ARGV.join(' ')}"
end

def nodes
  kubectl "get nodes -o wide"
end

def verify
  system "helm template . | kubectl apply --context #{KUBECTL_CONTEXT} --dry-run=server -f -"
end

def playground
  godmode = !!ARGV.delete("--privileged")
  host_network = !!ARGV.delete("--host-network")

  if host_network && !godmode
    abort "Error: --host-network requires --privileged"
  end

  node_hostname =
    if ARGV.empty?
      workers = read_kubectl("get nodes -o name").split("\n")
      worker_one = workers.find { |name| name.include?("worker-1") || name.include?("worker-01") }
      abort "Error: no worker-1 or worker-01 node found" unless worker_one

      worker_one = worker_one.delete_prefix("node/")
      puts "No node argument provided, defaulting to #{worker_one}"
      worker_one
    else
      ARGV.delete_at(0)
    end
  abort "Error: node '#{node_hostname}' not found" unless kubectl("get node #{node_hostname} &> /dev/null")

  require "securerandom"

  puts "Enabling privileged mode, use with caution!" if godmode
  puts "Enabling host network mode." if host_network

  image = "reclaimthestack/playground:20230206-154225"
  name = "playground-#{SecureRandom.hex(3)}"

  god_mounts =
    if godmode
      %(
        "volumeMounts": [{
          "mountPath": "/ephemeral",
          "name": "ephemeral"
        }],
      )
    end
  god_volumes =
    if godmode
      %(
        ,
        "volumes": [{
          "name": "ephemeral",
          "hostPath": {
            "path": "/var",
            "type": "Directory"
          }
        }]
      )
    end

  kubectl_command = %(
    kubectl --context #{KUBECTL_CONTEXT} run #{name} -it --restart=Never --rm --image #{image} \
    --overrides='
      {
        "apiVersion": "v1",
        "spec": {
          "nodeSelector": { "kubernetes.io/hostname": "#{node_hostname}" },
          "tolerations": [{ "operator": "Exists" }],
          "containers": [{
            "name": "#{name}",
            "image": "#{image}",
            "stdin": true,
            "stdinOnce": true,
            "tty": true,
            #{god_mounts}
            "securityContext": { "privileged": #{godmode} }
          }]
          #{god_volumes}
          #{host_network ? ', "hostNetwork": true' : ''}
        }
      }
    '
  )

  exec kubectl_command
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
    puts "k env-to-secret app.env <secret-name> | kubeseal --context #{KUBECTL_CONTEXT} -o yaml > applications/shared-secrets/<secret-name>.yaml"
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
         "your own clone of the gitops repository."
    puts ""
    puts "GENERATORS:"
    puts "k generate application <application-name>" + gray(" generates a new application")
    puts "k generate deployment <application-name> [<type>]" + gray(" generates a deployment for an application (web, sidekiq etc)")
    puts "k generate resource <application-name> [<type>]" + gray(" generates a resource for an application (postgres, redis etc)") # rubocop:disable Layout/LineLength
  end
end

def generate_application
  verify_inside_context_repository!

  application = ARGV.delete_at(0)
  abort "Must pass name of application to generate, eg. k generate application <application-name>" unless application
  abort "Error: Application name must only contain lower-case alphanumeric characters or '-'" unless application[/^[a-z-]+$/]

  directory = "applications/#{application}"

  abort "Error: An application named '#{application}' already exists" if File.exist?(directory)

  puts "Generating application skeleton..."
  puts

  Dir.mkdir(directory)
  Dir.mkdir("#{directory}/templates")

  chart_path = "#{directory}/Chart.yaml"
  File.write(
    chart_path,
    {
      "apiVersion" => "v2",
      "name" => application,
      "type" => "application",
      "version" => "1.0.0",
      "appVersion" => "1.0.0",
    }.to_yaml.delete_prefix("---\n")
  )
  puts "Created #{bold(chart_path)}"

  values_path = "#{directory}/values.yaml"
  File.write(
    values_path,
    {
      "deployments" => {},
      "resources" => {},
      "envFrom" => [],
      "env" => [],
    }.to_yaml.delete_prefix("---\n"),
  )
  puts "Created #{bold(values_path)}"

  template_gitkeep_path = "#{directory}/templates/.gitkeep"
  File.write(template_gitkeep_path, "")
  puts "Created #{bold(template_gitkeep_path)}"
end

def generate_deployment
  verify_inside_context_repository!

  application = ARGV.delete_at(0)
  abort "Must pass name of application, eg. k generate deployment <application> [<type>]" unless application

  app_path = "applications/#{application}"
  abort "Error: no application found at '#{app_path}'" unless File.directory?(app_path)

  values_path = "#{app_path}/values.yaml"
  abort "Error: no helm values found at '#{values_path}'" unless File.exist?(values_path)

  deployment_types = Dir.glob("generators/deployments/*.yaml").map { |path| File.basename(path, ".yaml") }
  abort "Error: no deployment generators found in 'generators/deployments'" if deployment_types.empty?

  # Sort deployments alphabetically, but put web first and other last if present
  deployment_types.sort!
  deployment_types.unshift deployment_types.delete("web") if deployment_types.include?("web")
  deployment_types.push deployment_types.delete("other") if deployment_types.include?("other")

  type = ARGV.delete_at(0)

  if type
    unless deployment_types.include?(type)
      abort "Error: invalid type '#{type}'\n\nMust be one of:\n#{deployment_types.join("\n")}"
    end
  else
    puts "What type of deployment do you wish to generate?"
    deployment_types.each_with_index do |type, index|
      puts "#{index + 1}. #{type.capitalize}"
    end
    selection = readline.to_i

    abort "Error: invalid selection" unless (1..deployment_types.length).include?(selection)
    type = deployment_types[selection - 1]
  end

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
    puts

    abort "Error: didn't provide a suffix" if suffix.empty?

    name = "#{name}-#{suffix}"
  end

  abort "Error: deployment name must only contain lower-case alphanumeric characters or '-'" unless name[/^[a-z0-9-]+$/]
  if File.exist?("#{app_path}/templates/deployment-#{name}.yaml")
    abort "Error: there is already an existing deployment named '#{name}'"
  end

  default_image = "#{REGISTRY}/#{application}:latest"

  camel_name = name.split("-").map.with_index { |word, i| i == 0 ? word : word.capitalize }.join
  deployment_template = format(
    File.read("generators/deployments/#{type}.yaml"),
    application: application,
    name: name,
    camelName: camel_name,
    image: default_image,
  )

  File.write("#{app_path}/templates/deployment-#{name}.yaml", deployment_template)
  puts "Created " + bold("#{app_path}/templates/deployment-#{name}.yaml")
  puts ""

  template_values_string = deployment_template
    .match(/# Example values\.yaml:\n([\s\S]*?)\n\n/)[1]
    .gsub(/^# /, "")
  values_string = File.read(values_path)
  template_values = YAML.load(template_values_string)
  values = YAML.load(values_string)

  # Handle image:
  if template_values.key?("image") && !values.key?("image")
    values_string.prepend("image: #{template_values['image']}\n")
  end

  # NOTE: We assume that 'deployments', 'envFrom' and 'env' nodes exists in all
  # application values.yaml files since "generate application" would create them.

  # Handle deployments:
  if template_values.key?("deployments")
    new_deployment_string = template_values_string.match(/^(deployments:.*?)(\n\S|\z)/m)[1]
    values_string.sub!(/^deployments:.*/, new_deployment_string)

    puts "Modified #{bold(values_path)} with new deployments configuration."
  end

  # Handle envFrom:
  if template_values["envFrom"].to_a.any? && values["envFrom"].none?
    new_env_from = template_values_string.match(/^(envFrom:.*?)(\n\S|\z)/m)[1]
    values_string.sub!(/^envFrom:.*/, new_env_from)

    puts "Modified #{bold(values_path)} with new envFrom configuration."
  end

  # Handle env:
  if template_values["env"].any?
    new_env = template_values_string.match(/^(env:.*?)(\n\S|\z)/m)[1]
    values_string.sub!(/^env:.*/, new_env)

    puts "Modified #{bold(values_path)} with additional env variables."
  end

  File.write(values_path, values_string)

  cloudflared_config_path = "platform/cloudflared/config.yaml"
  if type == "web" && File.exist?(cloudflared_config_path)
    domain = detect_deploy_domain
    cloudflared_config_string = File.read(cloudflared_config_path)

    new_ingress = <<~YAML
      ingress:
        - hostname: #{application}.#{domain}
          service: http://#{application}-web
    YAML
    cloudflared_config_string.sub!(/^ingress:.*\n/, new_ingress)

    File.write(cloudflared_config_path, cloudflared_config_string)

    puts "Modified #{bold(cloudflared_config_path)} with new ingress configuration."
  end

  puts
  puts "Please inspect all changes before you commit and push"
end

def generate_resource
  verify_inside_context_repository!

  application = ARGV.delete_at(0)
  abort "Must pass name of application, eg. k generate resource <application> [<type>]" unless application

  app_path = "applications/#{application}"
  abort "Error: no application found at '#{app_path}'" unless File.directory?(app_path)

  values_path = "#{app_path}/values.yaml"
  abort "Error: no helm values found at '#{values_path}'" unless File.exist?(values_path)

  resource_types = Dir.glob("generators/resources/*.yaml").map { |path| File.basename(path, ".yaml") }
  abort "Error: no deployment generators found in 'generators/deployments'" if resource_types.empty?

  type = ARGV.delete_at(0)
  if type && !resource_types.include?(type)
    abort "the resource type provided '#{type}' is not valid, must be one of #{resource_types.join(', ')}"
  end

  unless type
    puts "What type of deployment do you wish to generate?"
    resource_types.each_with_index do |type, index|
      puts "#{index + 1}. #{type.capitalize}"
    end
    selection = readline.to_i
    puts
    abort "Error: invalid selection" unless (1..resource_types.length).include?(selection)
    type = resource_types[selection - 1]
  end

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
    File.read("generators/resources/#{type}.yaml"),
    application: application,
    name: name,
    camelName: camel_name,
    suffix: suffix,
  )

  File.write("#{app_path}/templates/#{name}.yaml", resource_template)
  puts "Created " + bold("#{app_path}/templates/#{name}.yaml")
  puts ""

  template_values_string = resource_template
    .match(/# Example values\.yaml:\n([\s\S]*?)\n\n/)[1]
    .gsub(/^# /, "")
  values_string = File.read(values_path)
  template_values = YAML.load(template_values_string)
  values = YAML.load(values_string)

  # NOTE: We assume that 'resources', 'envFrom' and 'env' nodes exists in all
  # application values.yaml files since "generate application" would create them.

  # Handle resources:
  if template_values.key?("resources")
    new_resources_string = template_values_string.match(/^(resources:.*?)(\n\S|\z)/m)[1]
    values_string.sub!(/^resources:.*/, new_resources_string)

    puts "Modified #{bold(values_path)} with new resources configuration."
  end

  # Handle envFrom:
  if template_values["envFrom"].to_a.any? && values["envFrom"].none?
    new_env_from = template_values_string.match(/^(envFrom:.*?)(\n\S|\z)/m)[1]
    values_string.sub!(/^envFrom:.*/, new_env_from)

    puts "Modified #{bold(values_path)} with new envFrom configuration."
  end

  # Handle env:
  if template_values["env"].any?
    new_env = template_values_string.match(/^(env:.*?)(\n\S|\z)/m)[1]
    values_string.sub!(/^env:.*/, new_env)

    puts "Modified #{bold(values_path)} with additional env variables."
  end

  File.write(values_path, values_string)

  puts
  puts "Please inspect and tweak all changes before you commit and push"
end

def restart
  application = ARGV.delete_at(0)
  abort "Must pass name of application, eg. k restart <application>" unless application

  in_argo_repo do
    deployments = Dir.glob("applications/#{application}/templates/deployment-*.yaml").map do |path|
      path.match(%r{applications/(.*?)/templates/deployment-(.*?).yaml}).captures.join("-")
    end
    abort "Error: no deployments found for #{application}" if deployments.empty?

    puts
    puts bold("Restarting deployments")
    deployments.each do |deployment|
      kubectl("rollout restart deployment/#{deployment}") or abort "Error: failed to restart deployment"
    end

    puts
    puts bold("Waiting for deployment rollouts to complete")
    deployments.each do |deployment|
      kubectl("rollout status deployment/#{deployment} --watch=true --timeout=1m") or abort "Error: failed to wait for rollout"
    end

    puts
    puts "All deployments restarted successfully 🚀"
  end
end

def redis_cli
  redis_cluster = ARGV.delete_at(0)
  abort "Must pass name of redis-cluster, eg. k redis:cli <cluster-name> [<arguments for redis-cli>]" unless redis_cluster

  endpoint_yaml = read_kubectl "get endpoints/#{redis_cluster}-redis-master -o yaml"
  abort "Error: no master endpoint found for #{redis_cluster} (looked for #{redis_cluster}-redis-master)" if endpoint_yaml.empty?

  endpoint = YAML.safe_load(endpoint_yaml)
  master_pod = endpoint.dig("subsets", 0, "addresses", 0, "targetRef", "name")
  abort "Error: no master pod name found in endpoint YAML for #{redis_cluster}-redis-master" unless master_pod

  puts "Running redis-cli on #{master_pod}..."
  kubectl "exec -c redis -it #{master_pod} -- redis-cli #{ARGV.join(" ")}"
end

# TODO: This should use sentinel failover instead of redis failover
def redis_failover
  redis_cluster = ARGV.delete_at(0)
  abort "Must pass name of redis cluster, eg. k redis:failover <cluster-name>" unless redis_cluster

  endpoint_yaml = read_kubectl "get endpoints/#{redis_cluster}-redis-master -o yaml"
  abort "Error: no master endpoint found for #{redis_cluster} (looked for #{redis_cluster}-redis-master)" if endpoint_yaml.empty?

  endpoint = YAML.safe_load(endpoint_yaml)
  master_pod = endpoint.dig("subsets", 0, "addresses", 0, "targetRef", "name")
  abort "Error: no master pod name found in endpoint YAML for #{redis_cluster}-redis-master" unless master_pod

  puts "Running redis-cli with FAILOVER command on #{master_pod}..."
  kubectl "exec -c redis -it #{master_pod} -- redis-cli FAILOVER"

  puts "Running redis-cli with CLIENT KILL TYPE normal on #{master_pod} for 30 seconds to evict existing connections..."
  30.times do
    kubectl "exec -c redis -it #{master_pod} -- redis-cli CLIENT KILL TYPE normal"
    sleep 1
  end
end

def redis_url
  redis_cluster = ARGV.delete_at(0)
  abort "Must pass name of redis cluster, eg. k redis:url <cluster-name>" unless redis_cluster

  endpoint_yaml = read_kubectl "get endpoints/#{redis_cluster}-redis-master -o yaml"
  abort "Error: no master endpoint found for #{redis_cluster} (looked for #{redis_cluster}-redis-master)" if endpoint_yaml.empty?

  puts "redis://#{redis_cluster}-redis-master.default.svc:6379"
end

def redis_sentinel_url
  redis_cluster = ARGV.delete_at(0)
  abort "Must pass name of redis cluster, eg. k redis:sentinel-url <cluster-name>" unless redis_cluster

  endpoint_yaml = read_kubectl "get endpoints/#{redis_cluster}-redis-master -o yaml"
  abort "Error: no master endpoint found for #{redis_cluster} (looked for #{redis_cluster}-redis-master)" if endpoint_yaml.empty?

  puts "redis-sentinel://rfs-#{redis_cluster}.default.svc:26379/mymaster"
end

def update
  abort "Error: k update is only supported when installed via brew for now" unless `which k`.include?("homebrew")

  puts "Updating k via `brew reinstall k`..."
  system "brew reinstall k"
end

PRIVATE_METHODS_AFTER_COMMANDS = private_methods - PRIVATE_METHODS_BEFORE_COMMANDS

def verify_inside_context_repository!
  context_repo = URI K_CONTEXT.fetch("repository").delete_suffix(".git").delete_suffix("/")
  current_repo = URI `git remote get-url origin`.strip.delete_suffix(".git").delete_suffix("/")

  unless context_repo.path == current_repo.path
    abort "Error: this command must be run from a clone of the context repository (#{context_repo})"
  end
end

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
      sha,
      sha[0..10],
      author,
      Time.parse(time),
      relative_time,
      subject.delete_prefix("#{application}: "),
      body,
    )
  end
end

def detect_deploy_domain(primary_subdomain = "argocd")
  in_argo_repo do
    if File.exist?("platform-applications/cloudflared.yaml")
      begin
        YAML.load_file("platform/cloudflared/config.yaml")
          .fetch("ingress")
          .find { |ingress| ingress["hostname"].start_with?(primary_subdomain) }
          .then { |ingress| ingress["hostname"].split(".").drop(1).join(".") }
      rescue StandardError
        "example.com"
      end
    else
      "example.com"
    end
  end
end

# rubocop:enable Style/StringConcatenation

def dispatch(command)
  command = "_exec" if command == "exec"
  method = command.split(/[:-]/).join("_")

  send method
rescue NoMethodError => e
  # If the NoMethodError happened inside of the actual command we want to raise it
  raise unless e.name.to_s == method.to_s

  did_you_mean = DidYouMean::SpellChecker.new(dictionary: PRIVATE_METHODS_AFTER_COMMANDS)
    .correct(method)
    .map { |suggestion| "'#{suggestion.to_s.split('_').join(':')}'" }
  puts "Error: no command called '#{command}'"
  puts ""
  puts "Perhaps you meant #{did_you_mean.join(' or ')}?" unless did_you_mean.empty?
  exit 1 # using 'abort' somehow automatically prints the Exception
rescue Interrupt
  exit
end

command = ARGV.delete_at(0)

if command
  dispatch(command)
else
  print_commands
end
