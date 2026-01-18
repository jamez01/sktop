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

# Sktop is a terminal-based Sidekiq monitoring tool similar to htop.
# It provides real-time visibility into Sidekiq processes, queues,
# workers, and job status with an interactive TUI.
#
# @example Running from command line
#   sktop -r redis://localhost:6379/0
#
# @example Using in Ruby code
#   Sktop.configure_redis(url: "redis://localhost:6379/0")
#   Sktop::CLI.new.run
#
# @see https://github.com/jamez01/sktop
module Sktop
  # Base error class for all Sktop errors
  class Error < StandardError; end

  class << self
    # Configure the Redis connection for Sidekiq client mode.
    #
    # @param url [String, nil] Redis connection URL (e.g., "redis://localhost:6379/0")
    # @param namespace [String, nil] Redis namespace for Sidekiq keys (currently unused)
    # @return [void]
    #
    # @example Configure with a custom Redis URL
    #   Sktop.configure_redis(url: "redis://myredis:6379/1")
    def configure_redis(url: nil, namespace: nil)
      options = {}
      options[:url] = url if url

      Sidekiq.configure_client do |config|
        config.redis = options
      end
    end
  end
end
