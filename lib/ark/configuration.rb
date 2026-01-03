# frozen_string_literal: true

require "yaml"
require "erb"

module Ark
  class Configuration
    attr_accessor :api_key, :api_url, :environment, :enabled,
                  :excluded_exceptions, :before_send, :async, :verify_ssl,
                  :development_environments
    attr_writer :release

    def initialize
      @api_key = ENV["ARK_API_KEY"]
      @api_url = ENV["ARK_API_URL"] || "http://localhost:3000"
      @environment = ENV["RAILS_ENV"] || ENV["RACK_ENV"] || "development"
      @enabled = true
      @async = true
      @verify_ssl = true
      @excluded_exceptions = [
        "ActiveRecord::RecordNotFound",
        "ActionController::RoutingError",
        "ActionController::InvalidAuthenticityToken",
        "ActionController::BadRequest"
      ]
      @before_send = nil
      @release = nil
      @development_environments = %w[development test cucumber]
    end

    # Load configuration from a YAML file
    def self.from_yaml(path)
      return nil unless File.exist?(path)

      yaml_content = File.read(path)
      parsed = YAML.safe_load(ERB.new(yaml_content).result, permitted_classes: [], permitted_symbols: [], aliases: true)
      return nil unless parsed.is_a?(Hash)

      config = new
      config.apply_yaml(parsed)
      config
    end

    def apply_yaml(hash)
      @api_key = hash["api_key"] if hash["api_key"]
      @api_url = hash["api_url"] if hash["api_url"]
      @environment = hash["env"] if hash["env"]
      @enabled = hash["enabled"] if hash.key?("enabled")
      @async = hash["async"] if hash.key?("async")
      @verify_ssl = hash["verify_ssl"] if hash.key?("verify_ssl")
      @release = hash["release"] || hash["revision"] if hash["release"] || hash["revision"]

      if hash["development_environments"].is_a?(Array)
        @development_environments = hash["development_environments"]
      end

      if hash["excluded_exceptions"].is_a?(Array)
        @excluded_exceptions += hash["excluded_exceptions"]
      end
    end

    # Auto-detect release/revision if not explicitly set
    # Priority: manual config > env vars > REVISION file > git
    def release
      @release ||= detect_release
    end

    private

    def detect_release
      # 1. Check common deployment env vars
      ENV["HEROKU_SLUG_COMMIT"] ||      # Heroku
        ENV["RENDER_GIT_COMMIT"] ||     # Render
        ENV["RAILWAY_GIT_COMMIT_SHA"] || # Railway
        ENV["REVISION"] ||              # Generic
        ENV["GIT_COMMIT"] ||            # Generic
        revision_from_file ||           # Capistrano REVISION file
        revision_from_git               # Git fallback
    end

    def revision_from_file
      # Capistrano creates a REVISION file during deployment
      revision_file = if defined?(Rails) && Rails.root
                        Rails.root.join("REVISION")
                      else
                        File.join(Dir.pwd, "REVISION")
                      end

      File.read(revision_file).strip if File.exist?(revision_file)
    rescue StandardError
      nil
    end

    def revision_from_git
      return nil unless git_available?

      result = `git rev-parse HEAD 2>/dev/null`.strip
      result.empty? ? nil : result
    rescue StandardError
      nil
    end

    def git_available?
      system("git rev-parse --git-dir >/dev/null 2>&1")
    end

    def enabled?
      return false if @api_key.nil? || @api_key.empty?
      return false unless @enabled
      return false if development_environments.include?(@environment)

      true
    end

    def report_data?
      enabled?
    end

    def should_capture?(exception)
      return false unless enabled?
      !excluded_exceptions.include?(exception.class.name)
    end
  end
end
