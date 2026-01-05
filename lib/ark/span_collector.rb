# frozen_string_literal: true

module Ark
  class SpanCollector
    MAX_SPANS = 100           # Limit spans per request
    MAX_SQL_LENGTH = 500      # Truncate long SQL queries
    MIN_DURATION_MS = 1       # Skip spans shorter than 1ms

    class << self
      def current
        Thread.current[:ark_span_collector]
      end

      def start
        Thread.current[:ark_span_collector] = new
      end

      def stop
        collector = Thread.current[:ark_span_collector]
        Thread.current[:ark_span_collector] = nil
        collector
      end

      def active?
        !Thread.current[:ark_span_collector].nil?
      end

      def record(span)
        current&.add(span)
      end
    end

    def initialize
      @spans = []
      @start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    def add(span)
      return if @spans.size >= MAX_SPANS
      return if span[:duration_ms] && span[:duration_ms] < MIN_DURATION_MS

      @spans << span
    end

    def spans
      @spans
    end

    def to_a
      @spans.map do |span|
        {
          type: span[:type],
          name: span[:name],
          duration_ms: span[:duration_ms]&.round(2),
          offset_ms: span[:offset_ms]&.round(2),
          metadata: span[:metadata]
        }.compact
      end
    end
  end

  # Subscribe to ActiveSupport::Notifications for automatic span collection
  module SpanSubscribers
    class << self
      def subscribe!
        subscribe_sql
        subscribe_view
        subscribe_cache
        subscribe_http if defined?(Faraday)
      end

      private

      def subscribe_sql
        ActiveSupport::Notifications.subscribe("sql.active_record") do |*args|
          next unless SpanCollector.active?

          event = ActiveSupport::Notifications::Event.new(*args)
          payload = event.payload

          # Skip schema queries and transactions
          next if payload[:name] == "SCHEMA" || payload[:name] == "TRANSACTION"
          next if payload[:sql]&.start_with?("BEGIN", "COMMIT", "ROLLBACK")

          sql = payload[:sql].to_s
          sql = sql[0, SpanCollector::MAX_SQL_LENGTH] + "..." if sql.length > SpanCollector::MAX_SQL_LENGTH

          SpanCollector.record(
            type: "sql",
            name: payload[:name] || "SQL",
            duration_ms: event.duration,
            metadata: {
              sql: sql,
              cached: payload[:cached] || false
            }
          )
        end
      end

      def subscribe_view
        ActiveSupport::Notifications.subscribe("render_template.action_view") do |*args|
          next unless SpanCollector.active?

          event = ActiveSupport::Notifications::Event.new(*args)
          payload = event.payload

          identifier = payload[:identifier].to_s
          # Extract just the template name from the full path
          template = identifier.split("/views/").last || identifier.split("/").last

          SpanCollector.record(
            type: "view",
            name: template,
            duration_ms: event.duration
          )
        end

        ActiveSupport::Notifications.subscribe("render_partial.action_view") do |*args|
          next unless SpanCollector.active?

          event = ActiveSupport::Notifications::Event.new(*args)
          payload = event.payload

          identifier = payload[:identifier].to_s
          partial = identifier.split("/views/").last || identifier.split("/").last

          SpanCollector.record(
            type: "partial",
            name: partial,
            duration_ms: event.duration
          )
        end
      end

      def subscribe_cache
        ActiveSupport::Notifications.subscribe("cache_read.active_support") do |*args|
          next unless SpanCollector.active?

          event = ActiveSupport::Notifications::Event.new(*args)
          payload = event.payload

          SpanCollector.record(
            type: "cache",
            name: "cache_read",
            duration_ms: event.duration,
            metadata: {
              key: payload[:key].to_s.truncate(100),
              hit: payload[:hit]
            }
          )
        end
      end

      def subscribe_http
        # Faraday instrumentation (if ark-faraday is used or Faraday is configured)
        ActiveSupport::Notifications.subscribe("request.faraday") do |*args|
          next unless SpanCollector.active?

          event = ActiveSupport::Notifications::Event.new(*args)
          payload = event.payload

          url = payload[:url]
          host = url.is_a?(URI) ? url.host : url.to_s.split("/")[2]

          SpanCollector.record(
            type: "http",
            name: "#{payload[:method].to_s.upcase} #{host}",
            duration_ms: event.duration,
            metadata: {
              method: payload[:method],
              host: host,
              status: payload[:status]
            }
          )
        end
      end
    end
  end
end
