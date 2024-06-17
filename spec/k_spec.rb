# frozen_string_literal: true

require "open3"
require "debug"
require "fileutils"
require "yaml"

PROJECT_ROOT = "#{__dir__}/.."
HOME = "#{PROJECT_ROOT}/tmp/dummy-home"
TEST_REPOSITORY_PATH = "#{HOME}/.k/test"

RSpec.describe "k" do
  attr_reader :out, :err, :status

  def k(arguments, debug: false)
    Dir.chdir("#{ENV['HOME']}/.k/test") do
      # With the regular #capture3 approach to testing output and status of k
      # execution we will not be able to see puts statements or initialize a
      # debugger if we want to get a better understanding of what k is doing.
      # Temporarily passing debug: true while figuring something out changes
      # execution to use #system instead which allows for more debugging options.
      return system("#{PROJECT_ROOT}/k #{arguments}") if debug

      out, err, status = Open3.capture3("#{PROJECT_ROOT}/k #{arguments}")
      @out = out
      @err = err
      @status = status
    end
  end

  before do
    # reset dummy HOME directory
    FileUtils.rm_rf(HOME)
    FileUtils.cp_r("#{PROJECT_ROOT}/spec/fixtures/dummy-home", HOME)

    # Since we can't commit a git repo within a git repo we initialize git here
    Dir.chdir(TEST_REPOSITORY_PATH) do
      `git init`
      `git remote add origin https://github.com/dummy-organization/dummy-repo`
    end

    ENV["HOME"] = HOME
    ENV["GIT_TERMINAL_PROMPT"] = "0"
  end

  describe "#generate_application" do
    it "requires an <application-name> and generates an application skeleton" do
      k "generate application"

      expect(err).to include "k generate application <application-name>"
      expect(status).not_to be_success

      app_name = "test-app"

      k "generate application #{app_name}"

      expect(out).to include "applications/#{app_name}/Chart.yaml"
      expect(out).to include "applications/#{app_name}/values.yaml"
      expect(out).to include "applications/#{app_name}/templates/.gitkeep"

      expect(YAML.load_file("#{TEST_REPOSITORY_PATH}/applications/#{app_name}/Chart.yaml")).to eq(
        "apiVersion" => "v2",
        "name" => app_name,
        "type" => "application",
        "version" => "1.0.0",
        "appVersion" => "1.0.0",
      )
      expect(YAML.load_file("#{TEST_REPOSITORY_PATH}/applications/#{app_name}/values.yaml")).to eq(
        "deployments" => {},
        "resources" => {},
        "envFrom" => [],
        "env" => [],
      )
      expect(File.exist?("#{TEST_REPOSITORY_PATH}/applications/#{app_name}/templates/.gitkeep")).to be true
    end
  end

  describe "#generate_deployment / #generate_resource" do
    it "generates templates and ingests configuration into values.yaml and cloudflared's config.yaml" do
      app_name = "test-app"
      type = "web"

      k "generate application #{app_name}"
      k "generate deployment #{app_name} #{type}"

      expect(out).to include "applications/#{app_name}/templates/deployment-#{type}.yaml"
      expect(out).to include "applications/#{app_name}/values.yaml"

      cloudflare_config = YAML.load_file("#{TEST_REPOSITORY_PATH}/platform/cloudflared/config.yaml")
      expect(cloudflare_config.fetch("ingress").first).to eq(
        "hostname" => "#{app_name}.test.mynewsdesk.dev",
        "service" => "http://#{app_name}-#{type}",
      )

      type = "postgres"
      k "generate resource #{app_name} #{type}"

      expect(out).to include "applications/#{app_name}/templates/#{type}.yaml"
      expect(out).to include "applications/#{app_name}/values.yaml"

      type = "sidekiq"
      k "generate deployment #{app_name} #{type}"

      expect(out).to include "applications/#{app_name}/templates/deployment-#{type}.yaml"
      expect(out).to include "applications/#{app_name}/values.yaml"

      type = "redis"
      k "generate resource #{app_name} #{type}"

      expect(out).to include "applications/#{app_name}/templates/#{type}.yaml"
      expect(out).to include "applications/#{app_name}/values.yaml"

      generated_values = File.read("#{TEST_REPOSITORY_PATH}/applications/#{app_name}/values.yaml")
      expect(generated_values).to eq File.read("spec/fixtures/generated-values-snapshot.yaml")

      # Update snapshot with:
      # File.write(
      #   "spec/fixtures/generated-values-snapshot.yaml",
      #   generated_values,
      # )
    end
  end
end
