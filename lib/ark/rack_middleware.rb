# frozen_string_literal: true

module Ark
  class RackMiddleware
    def initialize(app)
      @app = app
    end

    def call(env)
      begin
        response = @app.call(env)
      rescue Exception => e
        capture_exception(e, env)
        raise
      end

      response
    end

    private

    def capture_exception(exception, env)
      return unless Ark.configuration&.should_capture?(exception)

      context = extract_request_context(env)
      Ark.capture_exception(exception, context: context)
    end

    def extract_request_context(env)
      request = Rack::Request.new(env)

      context = {
        request: {
          url: request.url,
          method: request.request_method,
          ip: request.ip,
          user_agent: request.user_agent,
          params: filtered_params(request),
          headers: extract_headers(env)
        }
      }

      # Add session ID for user tracking (if session exists)
      session_id = extract_session_id(env)
      context[:session_id] = session_id if session_id

      context
    end

    def filtered_params(request)
      params = request.params.dup
      filter_sensitive!(params)
      params
    rescue StandardError
      {}
    end

    def filter_sensitive!(hash, depth = 0)
      return if depth > 5

      sensitive = %w[password password_confirmation token api_key secret credit_card cvv ssn]

      hash.each do |key, value|
        if sensitive.any? { |s| key.to_s.downcase.include?(s) }
          hash[key] = "[FILTERED]"
        elsif value.is_a?(Hash)
          filter_sensitive!(value, depth + 1)
        end
      end
    end

    def extract_headers(env)
      headers = {}
      env.each do |key, value|
        next unless key.start_with?("HTTP_")
        next if %w[HTTP_COOKIE HTTP_AUTHORIZATION].include?(key)

        header_name = key.sub("HTTP_", "").split("_").map(&:capitalize).join("-")
        headers[header_name] = value
      end
      headers
    end

    def extract_session_id(env)
      # Try to get session ID from Rack session
      session = env["rack.session"]
      return session.id.to_s if session&.respond_to?(:id) && session.id

      # Fallback: check for session ID in options (set by some session stores)
      session_id = env["rack.session.options"]&.dig(:id)
      return session_id.to_s if session_id

      nil
    rescue StandardError
      nil
    end
  end
end
