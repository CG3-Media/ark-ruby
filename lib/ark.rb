# frozen_string_literal: true

require "net/http"
require "json"
require "uri"

require_relative "ark/version"
require_relative "ark/configuration"
require_relative "ark/client"
require_relative "ark/rack_middleware"
require_relative "ark/rails" if defined?(Rails::Railtie)

module Ark
  class << self
    attr_accessor :configuration

    def configure
      self.configuration ||= Configuration.new
      yield(configuration) if block_given?
    end

    def capture_exception(exception, context: {})
      return unless configuration&.enabled?

      Client.new.send_event(
        exception_class: exception.class.name,
        message: exception.message,
        backtrace: exception.backtrace || [],
        context: context,
        environment: configuration.environment
      )
    end

    def capture_message(message, level: "error", context: {})
      return unless configuration&.enabled?

      Client.new.send_event(
        exception_class: "Ark::Message",
        message: message,
        backtrace: caller,
        context: context.merge(level: level),
        environment: configuration.environment
      )
    end
  end
end
