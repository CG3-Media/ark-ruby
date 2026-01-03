# frozen_string_literal: true

require "rails/railtie"

module Ark
  class Railtie < ::Rails::Railtie
    initializer "ark.configure", before: :initialize_logger do
      Ark.configure do |config|
        config.environment = Rails.env
      end
    end

    initializer "ark.exceptions_catcher", after: :initialize_logger do
      # Hook into Rails exception rendering (like Honeybadger does)
      if defined?(::ActionDispatch::DebugExceptions)
        ::ActionDispatch::DebugExceptions.prepend(Ark::ExceptionsCatcher)
      end
    end

    initializer "ark.error_subscriber" do
      # Rails 7+ error reporting for handled errors
      if defined?(Rails.error) && Rails.error.respond_to?(:subscribe)
        Rails.error.subscribe(Ark::ErrorSubscriber.new)
      end
    end

    initializer "ark.active_job" do
      ActiveSupport.on_load(:active_job) do
        include Ark::ActiveJobExtension
      end
    end

    config.after_initialize do
      if Ark.configuration&.enabled?
        Rails.logger.info "[Ark] Error tracking enabled (env: #{Ark.configuration.environment})"
      else
        Rails.logger.warn "[Ark] Error tracking disabled - set ARK_API_KEY to enable"
      end
    end
  end

  # Hook into Rails' exception rendering to capture unhandled errors
  module ExceptionsCatcher
    def render_exception(request, exception, *args)
      # Capture the exception before Rails renders the error page
      if Ark.configuration&.should_capture?(exception)
        context = extract_request_context(request)
        Ark.capture_exception(exception, context: context)
      end

      super
    end

    private

    def extract_request_context(request)
      {
        request: {
          url: request.url,
          method: request.request_method,
          ip: request.remote_ip,
          user_agent: request.user_agent,
          params: request.filtered_parameters
        }
      }
    rescue StandardError
      {}
    end
  end

  # Rails 7+ error subscriber for handled errors (Rails.error.handle)
  class ErrorSubscriber
    def report(error, handled:, severity:, context: {}, source: nil)
      # Only capture handled errors here - unhandled ones go through ExceptionsCatcher
      return unless handled
      return unless Ark.configuration&.should_capture?(error)

      Ark.capture_exception(error, context: context.merge(
        handled: handled,
        severity: severity,
        source: source
      ))
    end
  end

  module ActiveJobExtension
    extend ActiveSupport::Concern

    included do
      around_perform do |job, block|
        block.call
      rescue Exception => e
        Ark.capture_exception(e, context: {
          job: {
            class: job.class.name,
            job_id: job.job_id,
            queue: job.queue_name,
            arguments: safe_arguments(job)
          }
        })
        raise
      end

      def safe_arguments(job)
        job.arguments.map do |arg|
          case arg
          when String, Numeric, Symbol, TrueClass, FalseClass, NilClass
            arg
          when Hash
            arg.transform_values { |v| v.is_a?(String) ? v.truncate(100) : v.class.name }
          else
            arg.class.name
          end
        end
      rescue StandardError
        ["[unable to serialize]"]
      end
    end
  end
end
