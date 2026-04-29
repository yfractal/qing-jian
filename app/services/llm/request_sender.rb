# frozen_string_literal: true

require "net/http"
require "time"

module Llm
  module RequestSender
    private

    def send_request(body_json:, model:, prompt:)
      log_request_start(model: model, prompt: prompt)
      started_at_monotonic = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      response = if @requester
        @requester.call(body_json)
      else
        Net::HTTP.start(
          self.class::OPENROUTER_URI.host,
          self.class::OPENROUTER_URI.port,
          use_ssl: self.class::OPENROUTER_URI.scheme == "https",
          open_timeout: 15,
          read_timeout: 60
        ) do |http|
          req = Net::HTTP::Post.new(self.class::OPENROUTER_URI)
          req["Content-Type"] = "application/json"
          req["Authorization"] = "Bearer #{@api_key}"
          req.body = body_json
          http.request(req)
        end
      end

      log_request_finish(started_at_monotonic: started_at_monotonic)
      response
    end

    def log_request_start(model:, prompt:)
      Rails.logger.info("llm.request.start start_time=#{Time.current.iso8601(3)} model=#{model} prompt=#{prompt.to_s.squish}")
    end

    def log_request_finish(started_at_monotonic:)
      ended_at = Time.current
      duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at_monotonic) * 1000).round
      Rails.logger.info("llm.request.finish end_time=#{ended_at.iso8601(3)} duration_ms=#{duration_ms}")
    end
  end
end
