# frozen_string_literal: true

module Ark
  class TransactionTracker
    def initialize
      @buffer = []
      @mutex = Mutex.new
      @last_flush = Time.now
    end

    def track(endpoint:, method:, duration_ms:, status_code:, db_time_ms: nil, view_time_ms: nil, request_id: nil, metadata: {})
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
        timestamp: Time.now.utc.iso8601
      }.compact

      @mutex.synchronize do
        @buffer << transaction

        # Flush if buffer is full or enough time has passed
        if should_flush?
          flush_async
        end
      end
    rescue StandardError => e
      warn "[Ark] Failed to track transaction: #{e.message}"
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
    end

    def flush_async
      transactions = @buffer.dup
      @buffer.clear
      @last_flush = Time.now

      Thread.new { send_transactions(transactions) }
    end

    private

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
      http.open_timeout = 5
      http.read_timeout = 10

      request = Net::HTTP::Post.new(uri.path)
      request["Content-Type"] = "application/json"
      request["X-API-Key"] = Ark.configuration.api_key
      request["User-Agent"] = "ark-ruby/#{Ark::VERSION}"
      request.body = { transactions: transactions }.to_json

      response = http.request(request)

      unless response.is_a?(Net::HTTPSuccess)
        warn "[Ark] Transactions API returned #{response.code}: #{response.body}"
      end

      response
    rescue StandardError => e
      warn "[Ark] Failed to send transactions: #{e.message}"
    end
  end
end
