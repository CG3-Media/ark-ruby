# frozen_string_literal: true

module Ark
  class Client
    def send_event(exception_class:, message:, backtrace:, context: {}, environment: nil)
      return unless Ark.configuration&.enabled?

      payload = build_payload(exception_class, message, backtrace, context, environment)

      # Apply before_send callback if configured
      if Ark.configuration.before_send
        payload = Ark.configuration.before_send.call(payload)
        return if payload.nil?
      end

      if Ark.configuration.async
        send_async(payload)
      else
        send_sync(payload)
      end
    rescue StandardError => e
      warn "[Ark] Failed to send event: #{e.message}"
    end

    private

    def build_payload(exception_class, message, backtrace, context, environment)
      {
        event: {
          exception_class: exception_class,
          message: truncate(message, 10_000),
          backtrace: clean_backtrace(backtrace),
          context: enrich_context(context),
          environment: environment || Ark.configuration.environment,
          release: Ark.configuration.release,
          sdk: { name: "ark-ruby", version: Ark::VERSION }
        }.compact
      }
    end

    def truncate(string, max_length)
      return "" if string.nil?
      string.length > max_length ? "#{string[0...max_length]}..." : string
    end

    def clean_backtrace(backtrace)
      return [] if backtrace.nil?

      backtrace.first(50).map do |line|
        line.sub(%r{^.*/gems/}, "[gem]/")
      end
    end

    def enrich_context(context)
      base = {
        ruby_version: RUBY_VERSION,
        timestamp: Time.now.utc.iso8601,
        hostname: Socket.gethostname
      }

      if defined?(Rails)
        base[:rails_version] = Rails::VERSION::STRING
      end

      base.merge(context)
    rescue StandardError
      context
    end

    def send_async(payload)
      Thread.new { send_sync(payload) }
    end

    def send_sync(payload)
      uri = URI.parse("#{Ark.configuration.api_url}/api/v1/events")

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.verify_mode = Ark.configuration.verify_ssl ? OpenSSL::SSL::VERIFY_PEER : OpenSSL::SSL::VERIFY_NONE
      http.open_timeout = 5
      http.read_timeout = 5

      request = Net::HTTP::Post.new(uri.path)
      request["Content-Type"] = "application/json"
      request["X-API-Key"] = Ark.configuration.api_key
      request["User-Agent"] = "ark-ruby/#{Ark::VERSION}"
      request.body = payload.to_json

      response = http.request(request)

      unless response.is_a?(Net::HTTPSuccess)
        warn "[Ark] API returned #{response.code}: #{response.body}"
      end

      response
    end
  end
end
