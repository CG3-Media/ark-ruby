# frozen_string_literal: true

module Ark
  class Configuration
    attr_accessor :api_key, :api_url, :environment, :enabled,
                  :excluded_exceptions, :before_send, :async

    def initialize
      @api_key = ENV["ARK_API_KEY"]
      @api_url = ENV["ARK_API_URL"] || "http://localhost:3000"
      @environment = ENV["RAILS_ENV"] || ENV["RACK_ENV"] || "development"
      @enabled = true
      @async = true
      @excluded_exceptions = [
        "ActiveRecord::RecordNotFound",
        "ActionController::RoutingError",
        "ActionController::InvalidAuthenticityToken",
        "ActionController::BadRequest"
      ]
      @before_send = nil
    end

    def enabled?
      @enabled && !@api_key.nil? && !@api_key.empty?
    end

    def should_capture?(exception)
      return false unless enabled?
      !excluded_exceptions.include?(exception.class.name)
    end
  end
end
