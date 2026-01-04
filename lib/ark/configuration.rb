# frozen_string_literal: true

require "yaml"
require "erb"

module Ark
  class Configuration
    attr_accessor :api_key, :api_url, :environment, :enabled,
                  :excluded_exceptions, :before_send, :async, :verify_ssl
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
      @env_configured = false  # Track if current env has config
    end

    # Load configuration from a YAML file (supports environment-specific config like database.yml)
    def self.from_yaml(path, env = nil)
      return nil unless File.exist?(path)

      yaml_content = File.read(path)
      parsed = YAML.safe_load(ERB.new(yaml_content).result, permitted_classes: [], permitted_symbols: [], aliases: true)
      return nil unless parsed.is_a?(Hash)

      config = new
      config.apply_yaml(parsed, env)
      config
    end

    def apply_yaml(hash, env = nil)
      env ||= @environment

      # Check if this is environment-specific config (has environment keys)
      env_keys = %w[production development staging test]
      has_env_config = env_keys.any? { |k| hash.key?(k) } || hash.key?("default")

      if has_env_config
        # Environment-specific config - only enable if current env is defined
        defaults = hash["default"] || {}
        env_config = hash[env]

        if env_config || defaults.any?
          @env_configured = true
          merged = deep_merge(defaults, env_config || {})
          apply_env_config(merged)
        end
        # If no config for this env and no defaults, @env_configured stays false
      else
        # Flat config (legacy format) - always configured
        @env_configured = true
        apply_flat_config(hash)
      end
    end

    # Auto-detect release/revision if not explicitly set
    # Priority: manual config > env vars > REVISION file > git
    def release
      @release ||= detect_release
    end

    def enabled?
      return false unless @env_configured
      return false if @api_key.nil? || @api_key.empty?
      return false unless @enabled

      true
    end

    def report_data?
      enabled?
    end

    def should_capture?(exception)
      return false unless enabled?
      !excluded_exceptions.include?(exception.class.name)
    end

    private

    def apply_flat_config(hash)
      @api_key = hash["api_key"] if hash["api_key"]
      @api_url = hash["api_url"] || hash["url"] if hash["api_url"] || hash["url"]
      @environment = hash["env"] if hash["env"]
      @enabled = hash["enabled"] if hash.key?("enabled")
      @async = hash["async"] if hash.key?("async")
      @verify_ssl = hash["verify_ssl"] if hash.key?("verify_ssl")
      @release = hash["release"] || hash["revision"] if hash["release"] || hash["revision"]

      if hash["excluded_exceptions"].is_a?(Array)
        @excluded_exceptions += hash["excluded_exceptions"]
      end
    end

    def apply_env_config(hash)
      # Handle nested api: structure
      api = hash["api"] || hash
      @api_key = api["key"] if api["key"]
      @api_url = api["url"] if api["url"]
      @environment = api["env"] if api["env"]
      @enabled = api["enabled"] if api.key?("enabled")
      @release = api["release"] || api["revision"] if api["release"] || api["revision"]
    end

    def deep_merge(base, override)
      return override if base.nil?
      return base if override.nil?

      base.merge(override) do |_key, old_val, new_val|
        if old_val.is_a?(Hash) && new_val.is_a?(Hash)
          deep_merge(old_val, new_val)
        else
          new_val
        end
      end
    end

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
  end
end
