# frozen_string_literal: true

require "optparse"
require "redis"
require "redis-namespace"
require "io/console"
require "io/wait"

module Sktop
  # Command-line interface for the Sktop Sidekiq monitor.
  # Handles argument parsing, Redis configuration, and the main event loop.
  #
  # @example Basic usage
  #   Sktop::CLI.new.run
  #
  # @example With custom arguments
  #   Sktop::CLI.new(["-r", "redis://myhost:6379/1", "-q"]).run
  class CLI
    # Create a new CLI instance.
    #
    # @param args [Array<String>] command-line arguments (defaults to ARGV)
    def initialize(args = ARGV)
      @args = args
      @options = {
        redis_url: ENV["REDIS_URL"] || "redis://localhost:6379/0",
        namespace: ENV["SIDEKIQ_NAMESPACE"],
        refresh_interval: 2,
        initial_view: :main,
        once: false
      }
      @running = true
    end

    # Run the CLI application.
    # Parses options, configures Redis, and starts the TUI.
    #
    # @return [void]
    # @raise [SystemExit] on connection errors or interrupts
    def run
      parse_options!
      configure_redis
      start_watcher
    rescue Interrupt
      shutdown
    rescue RedisClient::CannotConnectError, Redis::CannotConnectError => e
      shutdown
      puts "Error: Cannot connect to Redis at #{@options[:redis_url]}"
      puts "Make sure Redis is running and the URL is correct."
      puts "You can specify a different URL with: sktop -r redis://host:port/db"
      exit 1
    rescue StandardError => e
      shutdown
      puts "Error: #{e.message}"
      puts e.backtrace.first(5).join("\n") if ENV["DEBUG"]
      exit 1
    end

    # Gracefully shutdown the application.
    # Restores terminal state and shows the cursor.
    #
    # @return [void]
    def shutdown
      @running = false
      print "\e[?25h"    # Show cursor
      print "\e[?1049l"  # Restore main screen
      $stdout.flush
    end

    private

    # Parse command-line options and populate @options hash.
    # @return [void]
    # @api private
    def parse_options!
      parser = OptionParser.new do |opts|
        opts.banner = "Usage: sktop [options]"
        opts.separator ""
        opts.separator "Options:"

        opts.on("-r", "--redis URL", "Redis URL (default: redis://localhost:6379/0)") do |url|
          @options[:redis_url] = url
        end

        opts.on("-n", "--namespace NS", "Redis namespace (e.g., 'myapp')") do |ns|
          @options[:namespace] = ns
        end

        opts.on("-i", "--interval SECONDS", Integer, "Refresh interval in seconds (default: 2)") do |interval|
          @options[:refresh_interval] = interval
        end

        opts.separator ""
        opts.separator "Views (set initial view):"

        opts.on("-m", "--main", "Main view (default)") do
          @options[:initial_view] = :main
        end

        opts.on("-q", "--queues", "Queues view") do
          @options[:initial_view] = :queues
        end

        opts.on("-p", "--processes", "Processes view") do
          @options[:initial_view] = :processes
        end

        opts.on("-w", "--workers", "Workers view") do
          @options[:initial_view] = :workers
        end

        opts.on("-R", "--retries", "Retries view") do
          @options[:initial_view] = :retries
        end

        opts.on("-s", "--scheduled", "Scheduled jobs view") do
          @options[:initial_view] = :scheduled
        end

        opts.on("-d", "--dead", "Dead jobs view") do
          @options[:initial_view] = :dead
        end

        opts.on("-b", "--batches", "Batches view (Pro/Enterprise)") do
          @options[:initial_view] = :batches
        end

        opts.on("-c", "--cron", "Periodic/Cron jobs view (Enterprise)") do
          @options[:initial_view] = :periodic
        end

        opts.separator ""

        opts.on("-1", "--once", "Display once and exit (no auto-refresh)") do
          @options[:once] = true
        end

        opts.on("-v", "--version", "Show version") do
          puts "sktop #{Sktop::VERSION}"
          exit 0
        end

        opts.on("-h", "--help", "Show this help") do
          puts opts
          exit 0
        end
      end

      parser.parse!(@args)
    end

    # Configure Sidekiq's Redis connection from CLI options.
    # @return [void]
    # @api private
    def configure_redis
      Sidekiq.configure_client do |config|
        if @options[:namespace]
          config.redis = {
            url: @options[:redis_url],
            namespace: @options[:namespace]
          }
        else
          config.redis = { url: @options[:redis_url] }
        end
      end
    end

    # Start the main TUI loop with background data fetching.
    # Handles both one-shot mode and interactive auto-refresh mode.
    # @return [void]
    # @api private
    def start_watcher
      collector = StatsCollector.new
      @display = Display.new
      @display.current_view = @options[:initial_view]

      if @options[:once]
        # One-shot mode: just print and exit
        puts @display.render(collector)
        return
      end

      # Auto-refresh mode with keyboard input
      $stdout.sync = true

      # Get terminal size before entering raw mode
      @display.update_terminal_size

      # Switch to alternate screen buffer (like htop/vim)
      print "\e[?1049h"  # Enable alternate screen
      print "\e[?25l"    # Hide cursor
      print "\e[2J"      # Clear screen
      $stdout.flush

      # Thread-safe data cache
      @cached_data = nil
      @data_version = 0
      @rendered_version = 0
      @data_mutex = Mutex.new
      @fetch_in_progress = false
      @fetch_mutex = Mutex.new

      # Set up signal handler for Ctrl+C (works even when blocked)
      Signal.trap("INT") { @running = false }

      # Render loading screen immediately
      @display.connection_status = :connecting
      @display.render_loading

      # Start background thread for data fetching
      fetch_thread = Thread.new do
        while @running
          # Skip if a fetch is already in progress (defensive guard)
          can_fetch = @fetch_mutex.synchronize do
            if @fetch_in_progress
              false
            else
              @fetch_in_progress = true
            end
          end

          next unless can_fetch

          begin
            @display.connection_status = :updating
            collector.refresh!
            # Cache a snapshot of the data
            snapshot = {
              overview: collector.overview,
              queues: collector.queues,
              processes: collector.processes,
              workers: collector.workers,
              retry_jobs: collector.retry_jobs(limit: 500),
              scheduled_jobs: collector.scheduled_jobs(limit: 500),
              dead_jobs: collector.dead_jobs(limit: 500),
              # Enterprise/Pro features
              edition: collector.edition,
              batches: collector.batches(limit: 500),
              periodic_jobs: collector.periodic_jobs
            }

            # If viewing queue jobs, refresh that data too
            if @display.current_view == :queue_jobs && @display.selected_queue
              snapshot[:queue_jobs] = collector.queue_jobs(@display.selected_queue, limit: 500)
            end

            @data_mutex.synchronize do
              # Preserve queue_jobs if not refreshed above but still in that view
              if @cached_data && @cached_data[:queue_jobs] && !snapshot[:queue_jobs]
                snapshot[:queue_jobs] = @cached_data[:queue_jobs]
              end
              @cached_data = snapshot
              @data_version += 1
            end
            @display.connection_status = :connected
          rescue => e
            @display.connection_status = :error
            # Will retry next interval
          ensure
            @fetch_mutex.synchronize { @fetch_in_progress = false }
          end

          # Sleep in small increments so we can exit quickly
          (@options[:refresh_interval] * 10).to_i.times do
            break unless @running
            sleep 0.1
          end
        end
      end

      begin
        # Set up raw mode for keyboard input
        STDIN.raw do |stdin|
          # Initial render (will show loading or data if already fetched)
          render_cached_data

          while @running
            # Wait for keyboard input with short timeout
            ready = IO.select([stdin], nil, nil, 0.03)

            if ready
              key = stdin.read_nonblock(1) rescue nil
              if key
                handle_keypress(key, stdin)
                # Immediate refresh on keypress
                render_cached_data
              end
            end

            # Check if background thread has new data
            current_version = @data_mutex.synchronize { @data_version }
            if current_version != @rendered_version
              @rendered_version = current_version
              render_cached_data
            end
          end
        end
      ensure
        # Stop fetch thread
        @running = false
        fetch_thread.join(0.5) rescue nil

        # Restore normal screen
        print "\e[?25h"    # Show cursor
        print "\e[?1049l"  # Disable alternate screen
        $stdout.flush

        # Reset signal handler
        Signal.trap("INT", "DEFAULT")
      end
    end

    # Render the display from the cached data snapshot.
    # Shows loading screen if no data is available yet.
    # @return [void]
    # @api private
    def render_cached_data
      data = @data_mutex.synchronize { @cached_data }
      if data
        @display.render_refresh_from_cache(data)
      else
        @display.render_loading
      end
    end

    # Handle a keyboard input event.
    # Routes to appropriate view or action handler.
    #
    # @param key [String] the key character pressed
    # @param stdin [IO] the stdin IO object for reading escape sequences
    # @return [void]
    # @api private
    def handle_keypress(key, stdin)
      case key
      when 'q', 'Q'
        @display.current_view = :queues
      when 'p', 'P'
        @display.current_view = :processes
      when 'w', 'W'
        @display.current_view = :workers
      when 'r', 'R'  # Retries view
        @display.current_view = :retries
      when 's', 'S'
        @display.current_view = :scheduled
      when 'd', 'D'
        @display.current_view = :dead
      when 'b', 'B'
        @display.current_view = :batches
      when 'c', 'C'
        @display.current_view = :periodic
      when 'm', 'M'
        @display.current_view = :main
      when "\r", "\n"  # Enter key
        handle_enter_action
      when "\x12"  # Ctrl+R - retry job
        handle_retry_action
      when "\x18"  # Ctrl+X - delete job
        handle_delete_action
      when "\x11"  # Ctrl+Q - quiet process
        handle_quiet_process_action
      when "\x0B"  # Ctrl+K - stop/kill process
        handle_stop_process_action
      when "\e"  # Escape sequence - could be arrow keys, Alt+key, or just Escape
        # Try to read more characters (arrow keys send \e[A, \e[B, etc.)
        if IO.select([stdin], nil, nil, 0.05)
          seq = stdin.read_nonblock(10) rescue ""
          case seq
          when "[A"  # Up arrow
            @display.select_up
          when "[B"  # Down arrow
            @display.select_down
          when "[C"  # Right arrow - next view
            @display.next_view
          when "[D"  # Left arrow - previous view
            @display.previous_view
          when "[5~"  # Page Up
            @display.page_up
          when "[6~"  # Page Down
            @display.page_down
          when "r", "R"  # Alt+R - Retry All
            handle_retry_all_action
          when "x", "X"  # Alt+X - Delete All
            handle_delete_all_action
          else
            # Just Escape key - go back or to main
            handle_escape_action
          end
        else
          # Just Escape key - go back or to main
          handle_escape_action
        end
      when "\u0003"  # Ctrl+C
        raise Interrupt
      end
    end

    # Handle Ctrl+R to retry the selected job.
    # Only works in retries and dead views.
    # @return [void]
    # @api private
    def handle_retry_action
      return unless [:retries, :dead].include?(@display.current_view)

      data = @data_mutex.synchronize { @cached_data }
      unless data
        @display.set_status("No data available")
        return
      end

      jobs = @display.current_view == :retries ? data[:retry_jobs] : data[:dead_jobs]
      selected_idx = @display.selected_index

      if jobs.empty?
        @display.set_status("No jobs to retry")
        return
      end

      if selected_idx >= jobs.length
        @display.set_status("Invalid selection")
        return
      end

      job = jobs[selected_idx]
      unless job[:jid]
        @display.set_status("Job has no JID")
        return
      end

      begin
        source = @display.current_view == :retries ? :retry : :dead
        Sktop::JobActions.retry_job(job[:jid], source)
        @display.set_status("Retrying #{job[:class]}")
        # Force data refresh
        @rendered_version = -1
      rescue => e
        @display.set_status("Error: #{e.message}")
      end
    end

    # Handle Ctrl+X to delete the selected job.
    # Works in retries, dead, and queue_jobs views.
    # @return [void]
    # @api private
    def handle_delete_action
      # Handle queue_jobs view separately
      if @display.current_view == :queue_jobs
        handle_delete_queue_job_action
        return
      end

      return unless [:retries, :dead].include?(@display.current_view)

      data = @data_mutex.synchronize { @cached_data }
      unless data
        @display.set_status("No data available")
        return
      end

      jobs = @display.current_view == :retries ? data[:retry_jobs] : data[:dead_jobs]
      selected_idx = @display.selected_index

      if jobs.empty?
        @display.set_status("No jobs to delete")
        return
      end

      if selected_idx >= jobs.length
        @display.set_status("Invalid selection")
        return
      end

      job = jobs[selected_idx]
      unless job[:jid]
        @display.set_status("Job has no JID")
        return
      end

      begin
        source = @display.current_view == :retries ? :retry : :dead
        Sktop::JobActions.delete_job(job[:jid], source)
        @display.set_status("Deleted #{job[:class]}")
        # Force data refresh
        @rendered_version = -1
      rescue => e
        @display.set_status("Error: #{e.message}")
      end
    end

    # Handle Alt+R to retry all jobs in the current view.
    # Only works in retries and dead views.
    # @return [void]
    # @api private
    def handle_retry_all_action
      return unless [:retries, :dead].include?(@display.current_view)

      begin
        source = @display.current_view == :retries ? :retry : :dead
        count = Sktop::JobActions.retry_all(source)
        @display.set_status("Retrying all #{count} jobs")
        @rendered_version = -1
      rescue => e
        @display.set_status("Error: #{e.message}")
      end
    end

    # Handle Alt+X to delete all jobs in the current view.
    # Only works in retries and dead views.
    # @return [void]
    # @api private
    def handle_delete_all_action
      return unless [:retries, :dead].include?(@display.current_view)

      begin
        source = @display.current_view == :retries ? :retry : :dead
        count = Sktop::JobActions.delete_all(source)
        @display.set_status("Deleted all #{count} jobs")
        @rendered_version = -1
      rescue => e
        @display.set_status("Error: #{e.message}")
      end
    end

    # Handle Ctrl+Q to quiet the selected Sidekiq process.
    # Only works in processes view.
    # @return [void]
    # @api private
    def handle_quiet_process_action
      return unless @display.current_view == :processes

      data = @data_mutex.synchronize { @cached_data }
      unless data
        @display.set_status("No data available")
        return
      end

      processes = data[:processes]
      selected_idx = @display.selected_index

      if processes.empty?
        @display.set_status("No processes")
        return
      end

      if selected_idx >= processes.length
        @display.set_status("Invalid selection")
        return
      end

      process = processes[selected_idx]
      unless process[:identity]
        @display.set_status("Process has no identity")
        return
      end

      begin
        Sktop::JobActions.quiet_process(process[:identity])
        @display.set_status("Quieting #{process[:hostname]}:#{process[:pid]}")
        @rendered_version = -1
      rescue => e
        @display.set_status("Error: #{e.message}")
      end
    end

    # Handle Ctrl+K to stop/kill the selected Sidekiq process.
    # Only works in processes view.
    # @return [void]
    # @api private
    def handle_stop_process_action
      return unless @display.current_view == :processes

      data = @data_mutex.synchronize { @cached_data }
      unless data
        @display.set_status("No data available")
        return
      end

      processes = data[:processes]
      selected_idx = @display.selected_index

      if processes.empty?
        @display.set_status("No processes")
        return
      end

      if selected_idx >= processes.length
        @display.set_status("Invalid selection")
        return
      end

      process = processes[selected_idx]
      unless process[:identity]
        @display.set_status("Process has no identity")
        return
      end

      begin
        Sktop::JobActions.stop_process(process[:identity])
        @display.set_status("Stopping #{process[:hostname]}:#{process[:pid]}")
        @rendered_version = -1
      rescue => e
        @display.set_status("Error: #{e.message}")
      end
    end

    # Handle Enter key to view jobs in the selected queue.
    # Only works in queues view.
    # @return [void]
    # @api private
    def handle_enter_action
      return unless @display.current_view == :queues

      data = @data_mutex.synchronize { @cached_data }
      unless data
        @display.set_status("No data available")
        return
      end

      queues = data[:queues]
      selected_idx = @display.selected_index

      if queues.empty?
        @display.set_status("No queues")
        return
      end

      if selected_idx >= queues.length
        @display.set_status("Invalid selection")
        return
      end

      queue = queues[selected_idx]
      queue_name = queue[:name]

      # Fetch jobs from the queue
      begin
        collector = StatsCollector.new
        jobs = collector.queue_jobs(queue_name, limit: 500)

        # Update cached data with queue jobs
        @data_mutex.synchronize do
          @cached_data[:queue_jobs] = jobs
        end

        @display.selected_queue = queue_name
        @display.current_view = :queue_jobs
        @display.set_status("Loaded #{jobs.length} jobs from #{queue_name}")
      rescue => e
        @display.set_status("Error loading queue: #{e.message}")
      end
    end

    # Handle Escape key to go back or return to main view.
    # From queue_jobs returns to queues, otherwise returns to main.
    # @return [void]
    # @api private
    def handle_escape_action
      if @display.current_view == :queue_jobs
        # Go back to queues view
        @display.current_view = :queues
        @display.selected_queue = nil
      else
        # Go to main view
        @display.current_view = :main
      end
    end

    # Handle Ctrl+X to delete a job from the current queue.
    # Only works in queue_jobs view.
    # @return [void]
    # @api private
    def handle_delete_queue_job_action
      return unless @display.current_view == :queue_jobs

      data = @data_mutex.synchronize { @cached_data }
      unless data
        @display.set_status("No data available")
        return
      end

      jobs = data[:queue_jobs] || []
      selected_idx = @display.selected_index
      queue_name = @display.selected_queue

      if jobs.empty?
        @display.set_status("No jobs to delete")
        return
      end

      if selected_idx >= jobs.length
        @display.set_status("Invalid selection")
        return
      end

      job = jobs[selected_idx]
      unless job[:jid]
        @display.set_status("Job has no JID")
        return
      end

      begin
        Sktop::JobActions.delete_queue_job(queue_name, job[:jid])
        @display.set_status("Deleted #{job[:class]}")

        # Refresh the queue jobs
        collector = StatsCollector.new
        new_jobs = collector.queue_jobs(queue_name, limit: 500)
        @data_mutex.synchronize do
          @cached_data[:queue_jobs] = new_jobs
        end
        @rendered_version = -1
      rescue => e
        @display.set_status("Error: #{e.message}")
      end
    end

  end
end
