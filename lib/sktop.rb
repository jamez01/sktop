# frozen_string_literal: true

require "sidekiq"
require "sidekiq/api"
require "terminal-table"
require "pastel"
require "tty-cursor"
require "tty-screen"

require_relative "sktop/version"
require_relative "sktop/stats_collector"
require_relative "sktop/job_actions"
require_relative "sktop/display"
require_relative "sktop/cli"

module Sktop
  class Error < StandardError; end

  class << self
    def configure_redis(url: nil, namespace: nil)
      options = {}
      options[:url] = url if url

      Sidekiq.configure_client do |config|
        config.redis = options
      end
    end
  end
end
