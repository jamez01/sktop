# frozen_string_literal: true

module Sktop
  module JobActions
    class << self
      def retry_job(jid, source)
        job = find_job(jid, source)
        raise "Job not found (JID: #{jid})" unless job

        job.retry
        true
      end

      def delete_job(jid, source)
        job = find_job(jid, source)
        raise "Job not found (JID: #{jid})" unless job

        job.delete
        true
      end

      def kill_job(jid, source)
        job = find_job(jid, source)
        raise "Job not found (JID: #{jid})" unless job

        job.kill
        true
      end

      def retry_all(source)
        set = get_set(source)
        count = set.size
        set.retry_all
        count
      end

      def delete_all(source)
        set = get_set(source)
        count = set.size
        set.clear
        count
      end

      def quiet_process(identity)
        process = find_process(identity)
        raise "Process not found (identity: #{identity})" unless process

        process.quiet!
        true
      end

      def stop_process(identity)
        process = find_process(identity)
        raise "Process not found (identity: #{identity})" unless process

        process.stop!
        true
      end

      private

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

      def find_process(identity)
        Sidekiq::ProcessSet.new.find { |p| p["identity"] == identity }
      end
    end
  end
end
