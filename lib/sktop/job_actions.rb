# frozen_string_literal: true

module Sktop
  # Provides methods for performing actions on Sidekiq jobs and processes.
  # All methods are class methods and can be called directly on the module.
  #
  # @example Retry a failed job
  #   Sktop::JobActions.retry_job("abc123", :retry)
  #
  # @example Delete a dead job
  #   Sktop::JobActions.delete_job("abc123", :dead)
  #
  # @example Quiet a Sidekiq process
  #   Sktop::JobActions.quiet_process("myhost:12345:abc")
  module JobActions
    class << self
      # Retry a specific job from the retry or dead queue.
      #
      # @param jid [String] the job ID to retry
      # @param source [Symbol] the source queue (:retry or :dead)
      # @return [Boolean] true if the job was successfully retried
      # @raise [RuntimeError] if the job is not found
      #
      # @example Retry a job from the retry queue
      #   Sktop::JobActions.retry_job("abc123def456", :retry)
      def retry_job(jid, source)
        job = find_job(jid, source)
        raise "Job not found (JID: #{jid})" unless job

        job.retry
        true
      end

      # Delete a specific job from the retry or dead queue.
      #
      # @param jid [String] the job ID to delete
      # @param source [Symbol] the source queue (:retry or :dead)
      # @return [Boolean] true if the job was successfully deleted
      # @raise [RuntimeError] if the job is not found
      def delete_job(jid, source)
        job = find_job(jid, source)
        raise "Job not found (JID: #{jid})" unless job

        job.delete
        true
      end

      # Kill a specific job, moving it to the dead queue.
      #
      # @param jid [String] the job ID to kill
      # @param source [Symbol] the source queue (:retry or :scheduled)
      # @return [Boolean] true if the job was successfully killed
      # @raise [RuntimeError] if the job is not found
      def kill_job(jid, source)
        job = find_job(jid, source)
        raise "Job not found (JID: #{jid})" unless job

        job.kill
        true
      end

      # Retry all jobs in a sorted set (retry or dead queue).
      #
      # @param source [Symbol] the source queue (:retry or :dead)
      # @return [Integer] the number of jobs retried
      def retry_all(source)
        set = get_set(source)
        count = set.size
        set.retry_all
        count
      end

      # Delete all jobs from a sorted set (retry or dead queue).
      #
      # @param source [Symbol] the source queue (:retry or :dead)
      # @return [Integer] the number of jobs deleted
      def delete_all(source)
        set = get_set(source)
        count = set.size
        set.clear
        count
      end

      # Delete a specific job from a named queue.
      #
      # @param queue_name [String] the name of the queue
      # @param jid [String] the job ID to delete
      # @return [Boolean] true if the job was successfully deleted
      # @raise [RuntimeError] if the job is not found in the queue
      def delete_queue_job(queue_name, jid)
        queue = Sidekiq::Queue.new(queue_name)
        job = queue.find { |j| j.jid == jid }
        raise "Job not found in queue #{queue_name} (JID: #{jid})" unless job

        job.delete
        true
      end

      # Send the QUIET signal to a Sidekiq process.
      # A quieted process stops fetching new jobs but finishes current work.
      #
      # @param identity [String] the process identity (e.g., "hostname:pid:tag")
      # @return [Boolean] true if the signal was sent successfully
      # @raise [RuntimeError] if the process is not found
      def quiet_process(identity)
        process = find_process(identity)
        raise "Process not found (identity: #{identity})" unless process

        process.quiet!
        true
      end

      # Send the STOP signal to a Sidekiq process.
      # This initiates a graceful shutdown of the process.
      #
      # @param identity [String] the process identity (e.g., "hostname:pid:tag")
      # @return [Boolean] true if the signal was sent successfully
      # @raise [RuntimeError] if the process is not found
      def stop_process(identity)
        process = find_process(identity)
        raise "Process not found (identity: #{identity})" unless process

        process.stop!
        true
      end

      private

      # Get the appropriate Sidekiq sorted set for a given source.
      #
      # @param source [Symbol] the source type (:retry, :dead, or :scheduled)
      # @return [Sidekiq::RetrySet, Sidekiq::DeadSet, Sidekiq::ScheduledSet]
      # @raise [RuntimeError] if the source is unknown
      # @api private
      def get_set(source)
        case source
        when :retry
          Sidekiq::RetrySet.new
        when :dead
          Sidekiq::DeadSet.new
        when :scheduled
          Sidekiq::ScheduledSet.new
        else
          raise "Unknown source: #{source}"
        end
      end

      # Find a job by JID in a sorted set.
      #
      # @param jid [String] the job ID to find
      # @param source [Symbol] the source type (:retry, :dead, or :scheduled)
      # @return [Sidekiq::SortedEntry, nil] the job entry or nil if not found
      # @api private
      def find_job(jid, source)
        set = get_set(source)

        # Try find_job first (available in newer Sidekiq versions)
        if set.respond_to?(:find_job)
          job = set.find_job(jid)
          return job if job
        end

        # Fall back to iterating through the set
        set.each do |entry|
          return entry if entry.jid == jid
        end

        nil
      end

      # Find a Sidekiq process by its identity string.
      #
      # @param identity [String] the process identity
      # @return [Sidekiq::Process, nil] the process or nil if not found
      # @api private
      def find_process(identity)
        Sidekiq::ProcessSet.new.find { |p| p["identity"] == identity }
      end
    end
  end
end
