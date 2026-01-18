# frozen_string_literal: true

module Sktop
  # Collects statistics and data from Sidekiq for display in the TUI.
  # Wraps the Sidekiq API to provide a consistent interface for querying
  # queues, processes, workers, and job data.
  #
  # @example Basic usage
  #   collector = Sktop::StatsCollector.new
  #   puts collector.overview[:processed]
  #   puts collector.queues.length
  #
  # @example Refreshing data
  #   collector = Sktop::StatsCollector.new
  #   loop do
  #     collector.refresh!
  #     display_stats(collector.overview)
  #     sleep 2
  #   end
  class StatsCollector
    # Create a new StatsCollector instance.
    # Initializes with fresh statistics from Sidekiq.
    def initialize
      @stats = Sidekiq::Stats.new
    end

    # Refresh the cached statistics from Sidekiq.
    # Call this method periodically to get updated data.
    #
    # @return [self] the collector instance for method chaining
    def refresh!
      @stats = Sidekiq::Stats.new
      self
    end

    # Get an overview of Sidekiq statistics.
    #
    # @return [Hash] overview statistics
    # @option return [Integer] :processed total jobs processed
    # @option return [Integer] :failed total jobs failed
    # @option return [Integer] :scheduled_size jobs in scheduled queue
    # @option return [Integer] :retry_size jobs in retry queue
    # @option return [Integer] :dead_size jobs in dead queue
    # @option return [Integer] :enqueued total jobs across all queues
    # @option return [Float] :default_queue_latency latency of default queue in seconds
    def overview
      {
        processed: @stats.processed,
        failed: @stats.failed,
        scheduled_size: @stats.scheduled_size,
        retry_size: @stats.retry_size,
        dead_size: @stats.dead_size,
        enqueued: @stats.enqueued,
        default_queue_latency: @stats.default_queue_latency
      }
    end

    # Get information about all Sidekiq queues.
    #
    # @return [Array<Hash>] array of queue information hashes
    # @option return [String] :name queue name
    # @option return [Integer] :size number of jobs in queue
    # @option return [Float] :latency queue latency in seconds
    # @option return [Boolean] :paused whether the queue is paused
    def queues
      Sidekiq::Queue.all.map do |queue|
        {
          name: queue.name,
          size: queue.size,
          latency: queue.latency,
          paused: queue.paused?
        }
      end
    end

    # Get information about all running Sidekiq processes.
    #
    # @return [Array<Hash>] array of process information hashes
    # @option return [String] :identity unique process identifier
    # @option return [String] :hostname the host running the process
    # @option return [Integer] :pid process ID
    # @option return [String, nil] :tag optional process tag
    # @option return [Time] :started_at when the process started
    # @option return [Integer] :concurrency number of worker threads
    # @option return [Integer] :busy number of threads currently processing
    # @option return [Array<String>] :queues queues this process listens to
    # @option return [Array<String>] :labels process labels
    # @option return [Boolean] :quiet whether the process is quieted
    # @option return [Boolean] :stopping whether the process is stopping
    # @option return [Integer, nil] :rss memory usage in KB
    def processes
      Sidekiq::ProcessSet.new.map do |process|
        # Use direct hash access for status flags - the method accessors
        # like stopping? can have broader semantics in some Sidekiq versions
        quiet_val = process["quiet"]
        stopping_val = process["stopping"]

        quiet_flag = quiet_val == true || quiet_val == "true"
        stopping_flag = stopping_val == true || stopping_val == "true"

        {
          identity: process["identity"],
          hostname: process["hostname"],
          pid: process["pid"],
          tag: process["tag"],
          started_at: Time.at(process["started_at"]),
          concurrency: process["concurrency"],
          busy: process["busy"],
          queues: process["queues"],
          labels: process["labels"] || [],
          quiet: quiet_flag,
          stopping: stopping_flag,
          rss: process["rss"]  # Memory in KB
        }
      end
    end

    # Get information about all currently running workers.
    #
    # @return [Array<Hash>] array of worker information hashes
    # @option return [String] :process_id the process identity
    # @option return [String] :thread_id the thread identifier
    # @option return [String] :queue the queue being processed
    # @option return [String] :class the job class name
    # @option return [Array] :args the job arguments
    # @option return [Time] :run_at when the job started
    # @option return [Float] :elapsed seconds since job started
    def workers
      Sidekiq::Workers.new.map do |process_id, thread_id, work|
        extract_worker_info(process_id, thread_id, work)
      end
    end

    # Extract worker information from Sidekiq's Workers API.
    # Handles both Sidekiq 6.x (hash-based) and 7.x (Work object) formats.
    #
    # @param process_id [String] the process identity
    # @param thread_id [String] the thread identifier
    # @param work [Hash, Sidekiq::Work] the work data (format depends on Sidekiq version)
    # @return [Hash] normalized worker information
    # @api private
    def extract_worker_info(process_id, thread_id, work)
      # Sidekiq 7+ returns Work objects, older versions return hashes
      if work.is_a?(Hash)
        # Older Sidekiq - work is a hash with string keys
        payload = work["payload"]
        {
          process_id: process_id,
          thread_id: thread_id,
          queue: work["queue"],
          class: payload["class"],
          args: payload["args"] || [],
          run_at: Time.at(work["run_at"]),
          elapsed: Time.now - Time.at(work["run_at"])
        }
      elsif work.respond_to?(:job)
        # Sidekiq 7+ Work object with job accessor
        job = work.job
        {
          process_id: process_id,
          thread_id: thread_id,
          queue: work.queue,
          class: job["class"],
          args: job["args"] || [],
          run_at: Time.at(work.run_at),
          elapsed: Time.now - Time.at(work.run_at)
        }
      else
        # Fallback for other versions - try payload
        payload = work.payload
        {
          process_id: process_id,
          thread_id: thread_id,
          queue: work.queue,
          class: payload["class"],
          args: payload["args"] || [],
          run_at: Time.at(work.run_at),
          elapsed: Time.now - Time.at(work.run_at)
        }
      end
    end

    # Get jobs from a specific queue.
    #
    # @param queue_name [String] the name of the queue
    # @param limit [Integer] maximum number of jobs to return (default: 100)
    # @return [Array<Hash>] array of job information hashes
    # @option return [String] :jid the job ID
    # @option return [String] :class the job class name
    # @option return [Array] :args the job arguments
    # @option return [Time, nil] :enqueued_at when the job was enqueued
    # @option return [Time, nil] :created_at when the job was created
    def queue_jobs(queue_name, limit: 100)
      queue = Sidekiq::Queue.new(queue_name)
      queue.first(limit).map do |job|
        {
          jid: job.jid,
          class: job.klass,
          args: job.args,
          enqueued_at: job.enqueued_at,
          created_at: job.created_at
        }
      end
    end

    # Get jobs from the scheduled queue.
    #
    # @param limit [Integer] maximum number of jobs to return (default: 10)
    # @return [Array<Hash>] array of scheduled job information hashes
    # @option return [String] :class the job class name
    # @option return [String] :queue the target queue
    # @option return [Array] :args the job arguments
    # @option return [Time] :scheduled_at when the job is scheduled to run
    # @option return [Time, nil] :created_at when the job was created
    def scheduled_jobs(limit: 10)
      Sidekiq::ScheduledSet.new.first(limit).map do |job|
        {
          class: job.klass,
          queue: job.queue,
          args: job.args,
          scheduled_at: job.at,
          created_at: job.created_at
        }
      end
    end

    # Get jobs from the retry queue.
    #
    # @param limit [Integer] maximum number of jobs to return (default: 10)
    # @return [Array<Hash>] array of retry job information hashes
    # @option return [String] :jid the job ID
    # @option return [String] :class the job class name
    # @option return [String] :queue the original queue
    # @option return [Array] :args the job arguments
    # @option return [Time, nil] :failed_at when the job failed
    # @option return [Integer] :retry_count number of retry attempts
    # @option return [String] :error_class the exception class name
    # @option return [String] :error_message the exception message
    def retry_jobs(limit: 10)
      Sidekiq::RetrySet.new.first(limit).map do |job|
        {
          jid: job.jid,
          class: job.klass,
          queue: job.queue,
          args: job.args,
          failed_at: job["failed_at"] ? Time.at(job["failed_at"]) : nil,
          retry_count: job["retry_count"],
          error_class: job["error_class"],
          error_message: job["error_message"]
        }
      end
    end

    # Get jobs from the dead (morgue) queue.
    #
    # @param limit [Integer] maximum number of jobs to return (default: 10)
    # @return [Array<Hash>] array of dead job information hashes
    # @option return [String] :jid the job ID
    # @option return [String] :class the job class name
    # @option return [String] :queue the original queue
    # @option return [Array] :args the job arguments
    # @option return [Time, nil] :failed_at when the job failed
    # @option return [String] :error_class the exception class name
    # @option return [String] :error_message the exception message
    def dead_jobs(limit: 10)
      Sidekiq::DeadSet.new.first(limit).map do |job|
        {
          jid: job.jid,
          class: job.klass,
          queue: job.queue,
          args: job.args,
          failed_at: job["failed_at"] ? Time.at(job["failed_at"]) : nil,
          error_class: job["error_class"],
          error_message: job["error_message"]
        }
      end
    end

    # Get historical statistics for processed and failed jobs.
    #
    # @param days [Integer] number of days of history to retrieve (default: 7)
    # @return [Hash] history data
    # @option return [Hash] :processed daily processed counts keyed by date
    # @option return [Hash] :failed daily failed counts keyed by date
    def history(days: 7)
      stats_history = Sidekiq::Stats::History.new(days)
      {
        processed: stats_history.processed,
        failed: stats_history.failed
      }
    end
  end
end
