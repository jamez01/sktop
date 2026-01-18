# frozen_string_literal: true

module Sktop
  class StatsCollector
    def initialize
      @stats = Sidekiq::Stats.new
    end

    def refresh!
      @stats = Sidekiq::Stats.new
      self
    end

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

    def workers
      Sidekiq::Workers.new.map do |process_id, thread_id, work|
        extract_worker_info(process_id, thread_id, work)
      end
    end

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

    def history(days: 7)
      stats_history = Sidekiq::Stats::History.new(days)
      {
        processed: stats_history.processed,
        failed: stats_history.failed
      }
    end
  end
end
