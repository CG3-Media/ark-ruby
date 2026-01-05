# frozen_string_literal: true

module Ark
  class TransactionTracker
    # Safety limits to prevent impact on host app
    MAX_BUFFER_SIZE = 500          # Drop old transactions if buffer grows too large
    MAX_PENDING_FLUSHES = 3        # Limit concurrent flush threads
    CIRCUIT_BREAKER_THRESHOLD = 5  # Consecutive failures before circuit opens
    CIRCUIT_BREAKER_TIMEOUT = 60   # Seconds to wait before retrying after circuit opens

    def initialize
      @buffer = []
      @mutex = Mutex.new
      @last_flush = Time.now
      @pending_flushes = 0
      @consecutive_failures = 0
      @circuit_opened_at = nil
    end

    def track(endpoint:, method:, duration_ms:, status_code:, db_time_ms: nil, view_time_ms: nil, request_id: nil, metadata: {}, spans: [])
      return unless Ark.configuration&.transactions_enabled?
      return if duration_ms < Ark.configuration.transaction_threshold_ms

      transaction = {
        endpoint: endpoint,
        method: method,
        duration_ms: duration_ms.to_i,
        db_time_ms: db_time_ms&.to_i,
        view_time_ms: view_time_ms&.to_i,
        status_code: status_code,
        request_id: request_id,
        metadata: metadata,
        spans: spans,
        timestamp: Time.now.utc.iso8601
      }.compact

      @mutex.synchronize do
        # Cap buffer size - drop oldest transactions if full
        if @buffer.size >= MAX_BUFFER_SIZE
          @buffer.shift(MAX_BUFFER_SIZE / 4) # Drop oldest 25%
        end

        @buffer << transaction

        # Flush if buffer is full or enough time has passed
        if should_flush?
          flush_async
        end
      end
    rescue StandardError => e
      # Never let tracking errors affect the host app
      warn "[Ark] Failed to track transaction: #{e.message}" if $DEBUG
    end

    def flush
      transactions = nil

      @mutex.synchronize do
        return if @buffer.empty?

        transactions = @buffer.dup
        @buffer.clear
        @last_flush = Time.now
      end

      send_transactions(transactions) if transactions&.any?
    rescue StandardError => e
      warn "[Ark] Failed to flush transactions: #{e.message}" if $DEBUG
    end

    def flush_async
      # Don't spawn more threads if we have too many pending
      return if @pending_flushes >= MAX_PENDING_FLUSHES

      # Check circuit breaker
      return if circuit_open?

      transactions = @buffer.dup
      @buffer.clear
      @last_flush = Time.now
      @pending_flushes += 1

      Thread.new do
        send_transactions(transactions)
      ensure
        @mutex.synchronize { @pending_flushes -= 1 }
      end
    rescue StandardError => e
      warn "[Ark] Failed to start flush thread: #{e.message}" if $DEBUG
    end

    private

    def circuit_open?
      return false if @circuit_opened_at.nil?

      if Time.now - @circuit_opened_at > CIRCUIT_BREAKER_TIMEOUT
        # Try to close circuit
        @mutex.synchronize do
          @circuit_opened_at = nil
          @consecutive_failures = 0
        end
        false
      else
        true
      end
    end

    def record_success
      @mutex.synchronize do
        @consecutive_failures = 0
        @circuit_opened_at = nil
      end
    end

    def record_failure
      @mutex.synchronize do
        @consecutive_failures += 1
        if @consecutive_failures >= CIRCUIT_BREAKER_THRESHOLD
          @circuit_opened_at = Time.now
          warn "[Ark] Circuit breaker opened - pausing transaction sending for #{CIRCUIT_BREAKER_TIMEOUT}s"
        end
      end
    end

    def should_flush?
      @buffer.size >= Ark.configuration.transaction_buffer_size ||
        (Time.now - @last_flush) >= Ark.configuration.transaction_flush_interval
    end

    def send_transactions(transactions)
      return if transactions.empty?

      uri = URI.parse("#{Ark.configuration.api_url}/api/v1/transactions")

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.verify_mode = Ark.configuration.verify_ssl ? OpenSSL::SSL::VERIFY_PEER : OpenSSL::SSL::VERIFY_NONE
      http.open_timeout = 3  # Reduced from 5s
      http.read_timeout = 5  # Reduced from 10s

      request = Net::HTTP::Post.new(uri.path)
      request["Content-Type"] = "application/json"
      request["X-API-Key"] = Ark.configuration.api_key
      request["User-Agent"] = "ark-ruby/#{Ark::VERSION}"
      request.body = { transactions: transactions }.to_json

      response = http.request(request)

      if response.is_a?(Net::HTTPSuccess)
        record_success
      else
        record_failure
        warn "[Ark] Transactions API returned #{response.code}" if $DEBUG
      end

      response
    rescue StandardError => e
      record_failure
      warn "[Ark] Failed to send transactions: #{e.message}" if $DEBUG
      nil
    end
  end
end
