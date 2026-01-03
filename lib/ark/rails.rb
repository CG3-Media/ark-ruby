# frozen_string_literal: true

require "rails/railtie"

module Ark
  class Railtie < ::Rails::Railtie
    initializer "ark.configure", before: :initialize_logger do
      Ark.configure do |config|
        config.environment = Rails.env
      end
    end

    initializer "ark.middleware" do |app|
      app.config.middleware.insert(0, Ark::RackMiddleware)
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
