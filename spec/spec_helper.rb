# frozen_string_literal: true

require "bundler/setup"

# Prevent the real sidekiq/api from loading
$LOADED_FEATURES << "sidekiq.rb"
$LOADED_FEATURES << "sidekiq/api.rb"

# Mock Sidekiq module and classes for testing without a real Redis connection
module Sidekiq
  class Stats
    attr_accessor :processed, :failed, :scheduled_size, :retry_size, :dead_size,
                  :enqueued, :default_queue_latency

    def initialize
      @processed = 0
      @failed = 0
      @scheduled_size = 0
      @retry_size = 0
      @dead_size = 0
      @enqueued = 0
      @default_queue_latency = 0.0
    end

    class History
      attr_reader :processed, :failed

      def initialize(days = 7)
        @processed = {}
        @failed = {}
      end
    end
  end

  class Queue
    attr_reader :name, :size, :latency

    def initialize(name = "default", size = 0, latency = 0.0)
      @name = name
      @size = size
      @latency = latency
    end

    def paused?
      false
    end

    def self.all
      []
    end
  end

  class ProcessSet
    include Enumerable

    def initialize(processes = [])
      @processes = processes
    end

    def each(&block)
      @processes.each(&block)
    end

    def map(&block)
      @processes.map(&block)
    end

    def find(&block)
      @processes.find(&block)
    end
  end

  class Workers
    include Enumerable

    def initialize(workers = [])
      @workers = workers
    end

    def each(&block)
      @workers.each(&block)
    end

    def map(&block)
      @workers.map(&block)
    end
  end

  class ScheduledSet
    include Enumerable

    def initialize(jobs = [])
      @jobs = jobs
    end

    def first(n)
      @jobs.first(n)
    end

    def each(&block)
      @jobs.each(&block)
    end

    def size
      @jobs.size
    end

    def find_job(jid)
      @jobs.find { |j| j.jid == jid }
    end

    def retry_all
      @jobs.size
    end

    def clear
      count = @jobs.size
      @jobs.clear
      count
    end
  end

  class RetrySet < ScheduledSet
  end

  class DeadSet < ScheduledSet
  end

  # Mock job entry
  class JobEntry
    attr_reader :jid, :klass, :queue, :args, :at, :created_at

    def initialize(attrs = {})
      @jid = attrs[:jid] || SecureRandom.hex(12)
      @klass = attrs[:klass] || "TestJob"
      @queue = attrs[:queue] || "default"
      @args = attrs[:args] || []
      @at = attrs[:at] || Time.now
      @created_at = attrs[:created_at] || Time.now
      @data = attrs[:data] || {}
    end

    def [](key)
      @data[key]
    end

    def retry
      true
    end

    def delete
      true
    end

    def kill
      true
    end
  end

  # Mock process entry
  class ProcessEntry
    def initialize(attrs = {})
      @data = {
        "identity" => attrs[:identity] || "host:1234:abc",
        "hostname" => attrs[:hostname] || "localhost",
        "pid" => attrs[:pid] || 1234,
        "tag" => attrs[:tag],
        "started_at" => attrs[:started_at] || Time.now.to_i,
        "concurrency" => attrs[:concurrency] || 10,
        "busy" => attrs[:busy] || 0,
        "queues" => attrs[:queues] || ["default"],
        "labels" => attrs[:labels] || [],
        "quiet" => attrs[:quiet] || false,
        "stopping" => attrs[:stopping] || false,
        "rss" => attrs[:rss] || 102400
      }
    end

    def [](key)
      @data[key]
    end

    def quiet!
      @data["quiet"] = true
    end

    def stop!
      @data["stopping"] = true
    end
  end

  def self.configure_client
    yield OpenStruct.new(redis: nil) if block_given?
  end
end

# Now require sktop which will use our mocks
require "sktop"

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups
  config.filter_run_when_matching :focus
  config.example_status_persistence_file_path = "spec/examples.txt"
  config.disable_monkey_patching!
  config.warnings = true

  config.default_formatter = "doc" if config.files_to_run.one?

  config.order = :random
  Kernel.srand config.seed
end
