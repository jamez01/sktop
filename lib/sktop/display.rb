# frozen_string_literal: true

module Sktop
  class Display
    attr_accessor :current_view, :connection_status, :last_update

    def initialize
      @pastel = Pastel.new
      @cursor = TTY::Cursor
      @current_view = :main
      @terminal_size = nil
      @scroll_offsets = Hash.new(0)  # Track scroll position per view
      @selected_index = Hash.new(0)  # Track selected row per view
      @status_message = nil
      @status_time = nil
      @connection_status = :connecting  # :connecting, :connected, :updating, :error
      @last_update = nil
    end

    def scroll_up
      @scroll_offsets[@current_view] = [@scroll_offsets[@current_view] - 1, 0].max
    end

    def scroll_down
      @scroll_offsets[@current_view] += 1
    end

    def select_up
      if selectable_view?
        @selected_index[@current_view] = [@selected_index[@current_view] - 1, 0].max
      else
        scroll_up
      end
    end

    def select_down
      if selectable_view?
        @selected_index[@current_view] += 1
      else
        scroll_down
      end
    end

    def selectable_view?
      [:processes, :retries, :dead].include?(@current_view)
    end

    def page_up(page_size = nil)
      page_size ||= default_page_size
      if selectable_view?
        @selected_index[@current_view] = [@selected_index[@current_view] - page_size, 0].max
      else
        @scroll_offsets[@current_view] = [@scroll_offsets[@current_view] - page_size, 0].max
      end
    end

    def page_down(page_size = nil)
      page_size ||= default_page_size
      if selectable_view?
        @selected_index[@current_view] += page_size
      else
        @scroll_offsets[@current_view] += page_size
      end
    end

    def default_page_size
      # Use terminal height minus header/footer overhead as page size
      [terminal_height - 8, 5].max
    end

    def selected_index
      @selected_index[@current_view]
    end

    def set_status(message)
      @status_message = message
      @status_time = Time.now
    end

    def reset_scroll
      @scroll_offsets[@current_view] = 0
    end

    def current_view=(view)
      @current_view = view
      # Don't reset scroll when switching views - preserve position
    end

    def reset_cursor
      print @cursor.move_to(0, 0)
      print @cursor.hide
      $stdout.flush
    end

    def show_cursor
      print @cursor.show
    end

    def update_terminal_size
      # Force refresh of terminal size using TTY::Screen
      height = TTY::Screen.height
      width = TTY::Screen.width
      if height > 0 && width > 0
        @terminal_size = [height, width]
      end
    end

    def render(collector)
      content_parts = build_output(collector)
      content_parts.reject { |p| p == :footer }.map(&:to_s).join("\n")
    end

    def render_refresh(collector)
      content = build_output(collector)
      render_with_overwrite(content)
    end

    def render_refresh_from_cache(data)
      @connection_status = :connected
      @last_update = Time.now
      cached = CachedData.new(data)
      content = build_output(cached)
      render_with_overwrite(content)
    end

    def render_loading
      lines = []
      lines << header_bar
      lines << ""
      lines << @pastel.cyan("  Connecting to Redis...")
      lines << ""
      lines << @pastel.dim("  Waiting for data...")
      lines << :footer
      render_with_overwrite(lines)
    end

    # Simple wrapper to make cached hash act like collector
    class CachedData
      def initialize(data)
        @data = data
      end

      def overview
        @data[:overview]
      end

      def queues
        @data[:queues]
      end

      def processes
        @data[:processes]
      end

      def workers
        @data[:workers]
      end

      def retry_jobs(limit: 50)
        @data[:retry_jobs]&.first(limit) || []
      end

      def scheduled_jobs(limit: 50)
        @data[:scheduled_jobs]&.first(limit) || []
      end

      def dead_jobs(limit: 50)
        @data[:dead_jobs]&.first(limit) || []
      end
    end

    private

    def build_output(collector)
      case @current_view
      when :queues
        build_queues_detail(collector)
      when :processes
        build_processes_detail(collector)
      when :workers
        build_workers_detail(collector)
      when :retries
        build_retries_detail(collector)
      when :scheduled
        build_scheduled_detail(collector)
      when :dead
        build_dead_detail(collector)
      else
        build_main_view(collector)
      end
    end

    def build_main_view(collector)
      queues = collector.queues
      processes = collector.processes

      lines = []
      lines << header_bar
      lines << ""
      stats_meters(collector.overview, processes).each_line(chomp: true) { |l| lines << l }
      lines << ""

      # Calculate available space for queues and processes
      # Fixed: header(1) + blank(1) + stats(6) + blank(1) + blank(1) + footer(1) = 11
      # Each section needs: section_bar(1) + header(1) = 2 lines overhead
      height = terminal_height
      fixed_overhead = 11
      section_overhead = 4  # 2 for queues section header, 2 for processes section header
      available_rows = height - fixed_overhead - section_overhead

      # Allocate rows based on actual data counts
      workers = collector.workers
      process_rows_needed = processes.length
      worker_rows_needed = workers.length
      total_needed = process_rows_needed + worker_rows_needed

      if total_needed <= available_rows
        # Everything fits
        max_process_rows = process_rows_needed
        max_worker_rows = worker_rows_needed
      else
        # Need to limit - split proportionally with minimum of 3 each
        min_rows = 3
        if available_rows >= min_rows * 2
          process_share = (available_rows * process_rows_needed.to_f / [total_needed, 1].max).round
          process_share = [[process_share, min_rows].max, available_rows - min_rows].min
          max_process_rows = process_share
          max_worker_rows = available_rows - process_share
        else
          max_process_rows = available_rows / 2
          max_worker_rows = available_rows - max_process_rows
        end
      end

      processes_section(processes, max_rows: max_process_rows).each_line(chomp: true) { |l| lines << l }
      lines << ""
      workers_section(workers, max_rows: max_worker_rows).each_line(chomp: true) { |l| lines << l }
      lines << :footer
      lines
    end

    def build_queues_detail(collector)
      lines = []
      lines << header_bar
      lines << ""
      # Calculate available rows: height - header(1) - blank(1) - section(1) - table_header(1) - footer(1) = height - 5
      max_rows = terminal_height - 5
      queues_scrollable(collector.queues, max_rows).each_line(chomp: true) { |l| lines << l }
      lines << :footer
      lines
    end

    def build_processes_detail(collector)
      lines = []
      lines << header_bar
      lines << ""
      max_rows = terminal_height - 5
      processes_selectable(collector.processes, max_rows).each_line(chomp: true) { |l| lines << l }
      lines << :footer
      lines
    end

    def build_workers_detail(collector)
      lines = []
      lines << header_bar
      lines << ""
      max_rows = terminal_height - 5
      workers_section(collector.workers, max_rows: max_rows, scrollable: true).each_line(chomp: true) { |l| lines << l }
      lines << :footer
      lines
    end

    def build_retries_detail(collector)
      lines = []
      lines << header_bar
      lines << ""
      max_rows = terminal_height - 5
      retries_scrollable(collector.retry_jobs(limit: 500), max_rows).each_line(chomp: true) { |l| lines << l }
      lines << :footer
      lines
    end

    def build_scheduled_detail(collector)
      lines = []
      lines << header_bar
      lines << ""
      max_rows = terminal_height - 5
      scheduled_scrollable(collector.scheduled_jobs(limit: 500), max_rows).each_line(chomp: true) { |l| lines << l }
      lines << :footer
      lines
    end

    def build_dead_detail(collector)
      lines = []
      lines << header_bar
      lines << ""
      max_rows = terminal_height - 5
      dead_scrollable(collector.dead_jobs(limit: 500), max_rows).each_line(chomp: true) { |l| lines << l }
      lines << :footer
      lines
    end

    def render_with_overwrite(content_parts)
      width = terminal_width
      height = terminal_height

      footer_content = function_bar
      lines = content_parts.reject { |p| p == :footer }.map(&:to_s)

      # Truncate content to fit screen (leave 1 line for footer)
      max_content_lines = height - 1
      lines = lines.first(max_content_lines)

      # Build output buffer
      output = String.new

      # Render each content line with explicit cursor positioning
      lines.each_with_index do |line, row|
        output << "\e[#{row + 1};1H"  # Move to row (1-indexed), column 1
        visible_length = visible_string_length(line)
        if visible_length > width
          output << truncate_to_width(line, width)
        else
          output << line
          output << " " * (width - visible_length)
        end
      end

      # Fill remaining rows with blank lines
      blank_line = " " * width
      (lines.length...max_content_lines).each do |row|
        output << "\e[#{row + 1};1H"
        output << blank_line
      end

      # Render footer on the last line
      output << "\e[#{height};1H"
      footer_visible = visible_string_length(footer_content)
      if footer_visible > width
        output << truncate_to_width(footer_content, width)
      else
        output << footer_content
        output << " " * (width - footer_visible)
      end

      print output
      $stdout.flush
    end

    def truncate_to_width(str, width)
      visible_len = 0
      result = ""
      in_escape = false
      escape_seq = ""

      str.each_char do |char|
        if char == "\e"
          in_escape = true
          escape_seq = char
        elsif in_escape
          escape_seq += char
          if char =~ /[a-zA-Z]/
            result += escape_seq
            in_escape = false
            escape_seq = ""
          end
        else
          if visible_len < width
            result += char
            visible_len += 1
          end
        end
      end

      # Pad if needed
      result + " " * [width - visible_len, 0].max
    end

    def visible_string_length(str)
      str.gsub(/\e\[[0-9;]*m/, '').length
    end

    def header_bar
      width = terminal_width
      timestamp = Time.now.strftime("%H:%M:%S")
      title = "sktop"

      # Connection status indicator
      status_text = case @connection_status
                    when :connecting
                      @pastel.yellow.on_blue(" ● Connecting ")
                    when :updating
                      @pastel.cyan.on_blue(" ↻ Updating ")
                    when :error
                      @pastel.red.on_blue(" ✗ Error ")
                    else # :connected
                      if @last_update
                        age = Time.now - @last_update
                        if age < 5
                          @pastel.green.on_blue(" ● Connected ")
                        else
                          @pastel.green.on_blue(" ● #{format_update_age(age)} ago ")
                        end
                      else
                        @pastel.green.on_blue(" ● Connected ")
                      end
                    end

      left = @pastel.white.on_blue.bold(" #{title} ")
      right = @pastel.white.on_blue.bold(" #{timestamp} ")

      left_len = visible_string_length(left)
      status_len = visible_string_length(status_text)
      right_len = visible_string_length(right)
      middle_width = width - left_len - status_len - right_len
      middle = @pastel.on_blue(" " * [middle_width, 0].max)

      left + status_text + middle + right
    end

    def format_update_age(seconds)
      if seconds < 60
        "#{seconds.round}s"
      elsif seconds < 3600
        "#{(seconds / 60).round}m"
      else
        "#{(seconds / 3600).round}h"
      end
    end

    def section_bar(title)
      width = terminal_width
      left = @pastel.black.on_green.bold(" #{title} ")
      left_len = visible_string_length(left)
      padding = @pastel.on_green(" " * (width - left_len))
      left + padding
    end

    def format_table_header(header)
      width = terminal_width
      header_len = header.length
      padding = width - header_len
      @pastel.black.on_cyan(header + " " * [padding, 0].max)
    end

    def stats_meters(overview, processes = [])
      width = terminal_width
      col_width = (width / 2) - 2

      lines = []

      # Calculate worker utilization
      total_busy = processes.sum { |p| p[:busy] || 0 }
      total_threads = processes.sum { |p| p[:concurrency] || 0 }

      # Worker utilization bar
      worker_bar = utilization_bar("Workers", total_busy, total_threads, col_width)
      lines << "  #{worker_bar}"
      lines << ""

      processed = format_number(overview[:processed])
      failed = format_number(overview[:failed])
      left = meter_line("Processed", processed, :green, col_width)
      right = meter_line("Failed", failed, overview[:failed] > 0 ? :red : :white, col_width)
      lines << "  #{left}  #{right}"

      enqueued = format_number(overview[:enqueued])
      scheduled = format_number(overview[:scheduled_size])
      left = meter_line("Enqueued", enqueued, overview[:enqueued] > 0 ? :yellow : :white, col_width)
      right = meter_line("Scheduled", scheduled, :cyan, col_width)
      lines << "  #{left}  #{right}"

      retries = format_number(overview[:retry_size])
      dead = format_number(overview[:dead_size])
      left = meter_line("Retries", retries, overview[:retry_size] > 0 ? :yellow : :white, col_width)
      right = meter_line("Dead", dead, overview[:dead_size] > 0 ? :red : :white, col_width)
      lines << "  #{left}  #{right}"

      latency = format_latency(overview[:default_queue_latency])
      left = meter_line("Latency", latency, overview[:default_queue_latency] > 1 ? :yellow : :green, col_width)
      lines << "  #{left}"

      lines.join("\n")
    end

    def utilization_bar(label, used, total, width)
      return "#{label}: No workers" if total == 0

      # Calculate bar width (leave room for label, brackets, and count)
      label_part = "#{label}: ["
      count_part = " #{used}/#{total}]"
      bar_width = width - label_part.length - count_part.length

      bar_width = [bar_width, 10].max  # Minimum bar width

      # Calculate fill amount
      percentage = used.to_f / total
      filled = (percentage * bar_width).round
      filled = [filled, bar_width].min

      # Determine color based on utilization
      color = if percentage < 0.5
                :green
              elsif percentage < 0.8
                :yellow
              else
                :red
              end

      # Build the bar
      filled_part = "|" * filled
      empty_part = " " * (bar_width - filled)

      colored_bar = @pastel.send(color, filled_part)

      "#{@pastel.cyan(label_part)}#{colored_bar}#{empty_part}#{@pastel.send(color, count_part)}"
    end

    def meter_line(label, value, color, width)
      label_str = "#{label}:"
      value_str = @pastel.send(color).bold(value.to_s)
      spacing = width - label_str.length - visible_string_length(value_str)
      spacing = 1 if spacing < 1
      "#{@pastel.cyan(label_str)}#{' ' * spacing}#{value_str}"
    end

    # Compact queues for main view
    def queues_compact(queues, max_rows: nil)
      width = terminal_width
      lines = []
      lines << section_bar("Queues (#{queues.length}) - Press 'q' for details")

      return lines.join("\n") + "\n" + @pastel.dim("  No queues") if queues.empty?

      # Calculate column widths
      name_width = [32, width - 40].max
      header = sprintf("  %-#{name_width}s %10s %10s %10s", "NAME", "SIZE", "LATENCY", "STATUS")
      lines << format_table_header(header)

      # Show as many as we have room for (default to all if no limit)
      display_count = max_rows ? [queues.length, max_rows].min : queues.length
      queues.first(display_count).each do |queue|
        lines << format_queue_row(queue, name_width)
      end

      if queues.length > display_count
        lines << @pastel.dim("  ... and #{queues.length - display_count} more queues")
      end

      lines.join("\n")
    end

    # Full queues view
    def queues_full(queues)
      width = terminal_width
      lines = []

      return @pastel.dim("  No queues") if queues.empty?

      name_width = [40, width - 40].max
      header = sprintf("  %-#{name_width}s %10s %10s %10s", "NAME", "SIZE", "LATENCY", "STATUS")
      lines << format_table_header(header)

      queues.each do |queue|
        lines << format_queue_row(queue, name_width)
      end

      lines.join("\n")
    end

    # Scrollable queues view
    def queues_scrollable(queues, max_rows)
      width = terminal_width
      lines = []

      scroll_offset = @scroll_offsets[@current_view]
      # Account for section bar and header in max_rows
      data_rows = max_rows - 2
      max_scroll = [queues.length - data_rows, 0].max
      scroll_offset = [[scroll_offset, 0].max, max_scroll].min
      @scroll_offsets[@current_view] = scroll_offset

      scroll_indicator = queues.length > data_rows ? " [#{scroll_offset + 1}-#{[scroll_offset + data_rows, queues.length].min}/#{queues.length}]" : ""
      lines << section_bar("Queues#{scroll_indicator} - ↑↓ to scroll, 'm' for main")

      return lines.join("\n") + "\n" + @pastel.dim("  No queues") if queues.empty?

      name_width = [40, width - 40].max
      header = sprintf("  %-#{name_width}s %10s %10s %10s", "NAME", "SIZE", "LATENCY", "STATUS")
      lines << format_table_header(header)

      queues.drop(scroll_offset).first(data_rows).each do |queue|
        lines << format_queue_row(queue, name_width)
      end

      remaining = queues.length - scroll_offset - data_rows
      if remaining > 0
        lines << @pastel.dim("  ↓ #{remaining} more")
      end

      lines.join("\n")
    end

    def format_queue_row(queue, name_width)
      name = truncate(queue[:name], name_width)
      size = format_number(queue[:size])
      latency = format_latency(queue[:latency])
      status = queue[:paused] ? "PAUSED" : "ACTIVE"

      size_colored = queue[:size] > 0 ? @pastel.yellow(sprintf("%10s", size)) : sprintf("%10s", size)
      status_colored = queue[:paused] ? @pastel.red(sprintf("%10s", status)) : @pastel.green(sprintf("%10s", status))

      sprintf("  %-#{name_width}s %s %10s %s", name, size_colored, latency, status_colored)
    end

    # Compact processes for main view
    def processes_section(processes, max_rows: nil, scrollable: false)
      width = terminal_width
      lines = []

      scroll_offset = scrollable ? @scroll_offsets[@current_view] : 0
      # Clamp scroll offset to valid range
      max_scroll = [processes.length - (max_rows || processes.length), 0].max
      scroll_offset = [[scroll_offset, 0].max, max_scroll].min
      @scroll_offsets[@current_view] = scroll_offset if scrollable

      scroll_indicator = scrollable && processes.length > (max_rows || processes.length) ? " [#{scroll_offset + 1}-#{[scroll_offset + (max_rows || processes.length), processes.length].min}/#{processes.length}]" : ""
      hint = scrollable ? "↑↓ to scroll, 'm' for main" : "Press 'p' for details"
      lines << section_bar("Processes (#{processes.length})#{scroll_indicator} - #{hint}")

      if processes.empty?
        lines << @pastel.dim("  No processes running")
        return lines.join("\n")
      end

      host_width = [20, (width - 80) / 2].max
      queue_width = [24, (width - 80) / 2].max

      header = sprintf("  %-#{host_width}s %6s %9s %8s %-#{queue_width}s %8s %8s", "HOST", "PID", "BUSY", "MEM", "QUEUES", "UPTIME", "STATUS")
      lines << format_table_header(header)

      # Show as many as we have room for (default to all if no limit)
      display_count = max_rows ? [processes.length - scroll_offset, max_rows].min : processes.length
      processes.drop(scroll_offset).first(display_count).each do |proc|
        lines << format_process_row(proc, host_width, queue_width)
      end

      remaining = processes.length - scroll_offset - display_count
      if remaining > 0
        lines << @pastel.dim("  ↓ #{remaining} more (use arrow keys to scroll)")
      end

      lines.join("\n")
    end

    # Full processes view
    def processes_full(processes)
      width = terminal_width
      lines = []

      if processes.empty?
        return @pastel.dim("  No processes running")
      end

      host_width = [26, (width - 80) / 2].max
      queue_width = [34, (width - 80) / 2].max

      header = sprintf("  %-#{host_width}s %6s %9s %8s %-#{queue_width}s %8s %8s", "HOST", "PID", "BUSY", "MEM", "QUEUES", "UPTIME", "STATUS")
      lines << format_table_header(header)

      processes.each do |proc|
        lines << format_process_row(proc, host_width, queue_width)
      end

      lines.join("\n")
    end

    # Selectable processes view with quiet/stop actions
    def processes_selectable(processes, max_rows)
      width = terminal_width
      lines = []

      scroll_offset = @scroll_offsets[@current_view]
      data_rows = max_rows - 3  # Account for section bar, header, and status line
      max_scroll = [processes.length - data_rows, 0].max
      scroll_offset = [[scroll_offset, 0].max, max_scroll].min
      @scroll_offsets[@current_view] = scroll_offset

      # Clamp selected index
      @selected_index[@current_view] = [[@selected_index[@current_view], 0].max, [processes.length - 1, 0].max].min

      # Auto-scroll to keep selection visible
      selected = @selected_index[@current_view]
      if selected < scroll_offset
        scroll_offset = selected
        @scroll_offsets[@current_view] = scroll_offset
      elsif selected >= scroll_offset + data_rows
        scroll_offset = selected - data_rows + 1
        @scroll_offsets[@current_view] = scroll_offset
      end

      scroll_indicator = processes.length > data_rows ? " [#{scroll_offset + 1}-#{[scroll_offset + data_rows, processes.length].min}/#{processes.length}]" : ""
      lines << section_bar("Processes#{scroll_indicator} - ↑↓ select, ^Q=quiet, ^K=stop, m=main")

      if processes.empty?
        lines << @pastel.dim("  No processes running")
        return lines.join("\n")
      end

      host_width = [26, (width - 80) / 2].max
      queue_width = [34, (width - 80) / 2].max

      header = sprintf("  %-#{host_width}s %6s %9s %8s %-#{queue_width}s %8s %8s", "HOST", "PID", "BUSY", "MEM", "QUEUES", "UPTIME", "STATUS")
      lines << format_table_header(header)

      processes.drop(scroll_offset).first(data_rows).each_with_index do |proc, idx|
        actual_idx = scroll_offset + idx
        row = format_process_row(proc, host_width, queue_width)

        if actual_idx == selected
          lines << @pastel.black.on_white(row + " " * [width - visible_string_length(row), 0].max)
        else
          lines << row
        end
      end

      remaining = processes.length - scroll_offset - data_rows
      if remaining > 0
        lines << @pastel.dim("  ↓ #{remaining} more")
      end

      # Status message
      if @status_message && @status_time && (Time.now - @status_time) < 3
        lines << @pastel.green("  #{@status_message}")
      end

      lines.join("\n")
    end

    def format_process_row(proc, host_width, queue_width)
      host = truncate(proc[:hostname], host_width)
      pid = proc[:pid].to_s
      busy = "#{proc[:busy]}/#{proc[:concurrency]}"
      mem = format_memory(proc[:rss])
      queues = truncate(proc[:queues].join(","), queue_width)
      uptime = format_time_ago(proc[:started_at])

      status = if proc[:quiet] && proc[:stopping]
                 @pastel.red("STOPPING")  # Quiet process now shutting down
               elsif proc[:quiet]
                 @pastel.yellow("QUIET")
               elsif proc[:stopping]
                 @pastel.red("STOPPING")
               else
                 @pastel.green("RUNNING")
               end

      busy_colored = proc[:busy] > 0 ? @pastel.yellow.bold(sprintf("%9s", busy)) : sprintf("%9s", busy)

      sprintf("  %-#{host_width}s %6s %s %8s %-#{queue_width}s %8s %s", host, pid, busy_colored, mem, queues, uptime, status)
    end

    def format_memory(kb)
      return "N/A" if kb.nil? || kb == 0

      if kb < 1024
        "#{kb}K"
      elsif kb < 1024 * 1024
        "#{(kb / 1024.0).round(1)}M"
      else
        "#{(kb / 1024.0 / 1024.0).round(2)}G"
      end
    end

    # Compact workers for main view
    def workers_section(workers, max_rows: nil, scrollable: false)
      width = terminal_width
      lines = []

      scroll_offset = scrollable ? @scroll_offsets[@current_view] : 0
      max_scroll = [workers.length - (max_rows || workers.length), 0].max
      scroll_offset = [[scroll_offset, 0].max, max_scroll].min
      @scroll_offsets[@current_view] = scroll_offset if scrollable

      scroll_indicator = scrollable && workers.length > (max_rows || workers.length) ? " [#{scroll_offset + 1}-#{[scroll_offset + (max_rows || workers.length), workers.length].min}/#{workers.length}]" : ""
      hint = scrollable ? "↑↓ to scroll, 'm' for main" : "Press 'w' for details"
      lines << section_bar("Active Workers (#{workers.length})#{scroll_indicator} - #{hint}")

      if workers.empty?
        lines << @pastel.dim("  No active workers")
        return lines.join("\n")
      end

      job_width = [30, (width - 50) / 2].max
      args_width = [30, (width - 50) / 2].max

      header = sprintf("  %-15s %-#{job_width}s %12s %-#{args_width}s", "QUEUE", "JOB", "RUNNING", "ARGS")
      lines << format_table_header(header)

      # Show as many as we have room for (default to all if no limit)
      display_count = max_rows ? [workers.length - scroll_offset, max_rows].min : workers.length
      workers.drop(scroll_offset).first(display_count).each do |worker|
        queue = truncate(worker[:queue], 15)
        job = truncate(worker[:class], job_width)
        running = format_duration(worker[:elapsed])
        args = truncate(worker[:args].inspect, args_width)

        running_colored = worker[:elapsed] > 60 ? @pastel.yellow(sprintf("%12s", running)) : sprintf("%12s", running)

        lines << sprintf("  %-15s %-#{job_width}s %s %-#{args_width}s", queue, job, running_colored, args)
      end

      remaining = workers.length - scroll_offset - display_count
      if remaining > 0
        lines << @pastel.dim("  ↓ #{remaining} more (use arrow keys to scroll)")
      end

      lines.join("\n")
    end

    # Full workers view
    def workers_full(workers)
      width = terminal_width
      lines = []

      if workers.empty?
        return @pastel.dim("  No active workers")
      end

      job_width = [40, (width - 50) / 2].max
      args_width = [40, (width - 50) / 2].max

      header = sprintf("  %-15s %-#{job_width}s %12s %-#{args_width}s", "QUEUE", "JOB", "RUNNING", "ARGS")
      lines << format_table_header(header)

      workers.each do |worker|
        queue = truncate(worker[:queue], 15)
        job = truncate(worker[:class], job_width)
        running = format_duration(worker[:elapsed])
        args = truncate(worker[:args].inspect, args_width)

        running_colored = worker[:elapsed] > 60 ? @pastel.yellow(sprintf("%12s", running)) : sprintf("%12s", running)

        lines << sprintf("  %-15s %-#{job_width}s %s %-#{args_width}s", queue, job, running_colored, args)
      end

      lines.join("\n")
    end

    # Full retries view
    def retries_full(jobs)
      width = terminal_width
      lines = []

      if jobs.empty?
        return @pastel.dim("  No retries pending")
      end

      job_width = [35, (width - 60) / 2].max
      error_width = [35, (width - 60) / 2].max

      header = sprintf("  %-#{job_width}s %-15s %6s %-#{error_width}s %16s", "JOB", "QUEUE", "COUNT", "ERROR", "FAILED AT")
      lines << format_table_header(header)

      jobs.each do |job|
        klass = truncate(job[:class], job_width)
        queue = truncate(job[:queue], 15)
        count = job[:retry_count].to_s
        error = truncate(job[:error_class].to_s, error_width)
        failed_at = job[:failed_at]&.strftime("%Y-%m-%d %H:%M") || "N/A"

        lines << sprintf("  %-#{job_width}s %-15s %6s %-#{error_width}s %16s",
                        klass, queue, @pastel.yellow(count), @pastel.red(error), failed_at)
      end

      lines.join("\n")
    end

    # Scrollable retries view with selection
    def retries_scrollable(jobs, max_rows)
      width = terminal_width
      lines = []

      scroll_offset = @scroll_offsets[@current_view]
      data_rows = max_rows - 3  # Account for section bar, header, and status line
      max_scroll = [jobs.length - data_rows, 0].max
      scroll_offset = [[scroll_offset, 0].max, max_scroll].min
      @scroll_offsets[@current_view] = scroll_offset

      # Clamp selected index
      @selected_index[@current_view] = [[@selected_index[@current_view], 0].max, [jobs.length - 1, 0].max].min

      # Auto-scroll to keep selection visible
      selected = @selected_index[@current_view]
      if selected < scroll_offset
        scroll_offset = selected
        @scroll_offsets[@current_view] = scroll_offset
      elsif selected >= scroll_offset + data_rows
        scroll_offset = selected - data_rows + 1
        @scroll_offsets[@current_view] = scroll_offset
      end

      scroll_indicator = jobs.length > data_rows ? " [#{scroll_offset + 1}-#{[scroll_offset + data_rows, jobs.length].min}/#{jobs.length}]" : ""
      lines << section_bar("Retry Queue#{scroll_indicator} - ↑↓ select, ^R=retry, ^X=del, Alt+R=retryAll, Alt+X=delAll")

      if jobs.empty?
        lines << @pastel.dim("  No retries pending")
        return lines.join("\n")
      end

      job_width = [35, (width - 60) / 2].max
      error_width = [35, (width - 60) / 2].max

      header = sprintf("  %-#{job_width}s %-15s %6s %-#{error_width}s %16s", "JOB", "QUEUE", "COUNT", "ERROR", "FAILED AT")
      lines << format_table_header(header)

      jobs.drop(scroll_offset).first(data_rows).each_with_index do |job, idx|
        actual_idx = scroll_offset + idx
        klass = truncate(job[:class], job_width)
        queue = truncate(job[:queue], 15)
        count = job[:retry_count].to_s
        error = truncate(job[:error_class].to_s, error_width)
        failed_at = job[:failed_at]&.strftime("%Y-%m-%d %H:%M") || "N/A"

        row = sprintf("  %-#{job_width}s %-15s %6s %-#{error_width}s %16s",
                      klass, queue, @pastel.yellow(count), @pastel.red(error), failed_at)

        if actual_idx == selected
          lines << @pastel.black.on_white(row + " " * [width - visible_string_length(row), 0].max)
        else
          lines << row
        end
      end

      remaining = jobs.length - scroll_offset - data_rows
      if remaining > 0
        lines << @pastel.dim("  ↓ #{remaining} more")
      end

      # Status message
      if @status_message && @status_time && (Time.now - @status_time) < 3
        lines << @pastel.green("  #{@status_message}")
      end

      lines.join("\n")
    end

    # Full scheduled view
    def scheduled_full(jobs)
      width = terminal_width
      lines = []

      if jobs.empty?
        return @pastel.dim("  No scheduled jobs")
      end

      job_width = [35, (width - 60) / 2].max
      args_width = [35, (width - 60) / 2].max

      header = sprintf("  %-#{job_width}s %-15s %-20s %-#{args_width}s", "JOB", "QUEUE", "SCHEDULED FOR", "ARGS")
      lines << format_table_header(header)

      jobs.each do |job|
        klass = truncate(job[:class], job_width)
        queue = truncate(job[:queue], 15)
        scheduled = job[:scheduled_at].strftime("%Y-%m-%d %H:%M:%S")
        args = truncate(job[:args].inspect, args_width)

        lines << sprintf("  %-#{job_width}s %-15s %-20s %-#{args_width}s", klass, queue, @pastel.cyan(scheduled), args)
      end

      lines.join("\n")
    end

    # Scrollable scheduled view
    def scheduled_scrollable(jobs, max_rows)
      width = terminal_width
      lines = []

      scroll_offset = @scroll_offsets[@current_view]
      data_rows = max_rows - 2
      max_scroll = [jobs.length - data_rows, 0].max
      scroll_offset = [[scroll_offset, 0].max, max_scroll].min
      @scroll_offsets[@current_view] = scroll_offset

      scroll_indicator = jobs.length > data_rows ? " [#{scroll_offset + 1}-#{[scroll_offset + data_rows, jobs.length].min}/#{jobs.length}]" : ""
      lines << section_bar("Scheduled Jobs#{scroll_indicator} - ↑↓ to scroll, 'm' for main")

      if jobs.empty?
        lines << @pastel.dim("  No scheduled jobs")
        return lines.join("\n")
      end

      job_width = [35, (width - 60) / 2].max
      args_width = [35, (width - 60) / 2].max

      header = sprintf("  %-#{job_width}s %-15s %-20s %-#{args_width}s", "JOB", "QUEUE", "SCHEDULED FOR", "ARGS")
      lines << format_table_header(header)

      jobs.drop(scroll_offset).first(data_rows).each do |job|
        klass = truncate(job[:class], job_width)
        queue = truncate(job[:queue], 15)
        scheduled = job[:scheduled_at].strftime("%Y-%m-%d %H:%M:%S")
        args = truncate(job[:args].inspect, args_width)

        lines << sprintf("  %-#{job_width}s %-15s %-20s %-#{args_width}s", klass, queue, @pastel.cyan(scheduled), args)
      end

      remaining = jobs.length - scroll_offset - data_rows
      if remaining > 0
        lines << @pastel.dim("  ↓ #{remaining} more")
      end

      lines.join("\n")
    end

    # Scrollable dead jobs view with selection
    def dead_scrollable(jobs, max_rows)
      width = terminal_width
      lines = []

      scroll_offset = @scroll_offsets[@current_view]
      data_rows = max_rows - 3  # Account for section bar, header, and status line
      max_scroll = [jobs.length - data_rows, 0].max
      scroll_offset = [[scroll_offset, 0].max, max_scroll].min
      @scroll_offsets[@current_view] = scroll_offset

      # Clamp selected index
      @selected_index[@current_view] = [[@selected_index[@current_view], 0].max, [jobs.length - 1, 0].max].min

      # Auto-scroll to keep selection visible
      selected = @selected_index[@current_view]
      if selected < scroll_offset
        scroll_offset = selected
        @scroll_offsets[@current_view] = scroll_offset
      elsif selected >= scroll_offset + data_rows
        scroll_offset = selected - data_rows + 1
        @scroll_offsets[@current_view] = scroll_offset
      end

      scroll_indicator = jobs.length > data_rows ? " [#{scroll_offset + 1}-#{[scroll_offset + data_rows, jobs.length].min}/#{jobs.length}]" : ""
      lines << section_bar("Dead Jobs#{scroll_indicator} - ↑↓ select, ^R=retry, ^X=del, Alt+R=retryAll, Alt+X=delAll")

      if jobs.empty?
        lines << @pastel.dim("  No dead jobs")
        return lines.join("\n")
      end

      job_width = [35, (width - 60) / 2].max
      error_width = [35, (width - 60) / 2].max

      header = sprintf("  %-#{job_width}s %-15s %-#{error_width}s %16s", "JOB", "QUEUE", "ERROR", "FAILED AT")
      lines << format_table_header(header)

      jobs.drop(scroll_offset).first(data_rows).each_with_index do |job, idx|
        actual_idx = scroll_offset + idx
        klass = truncate(job[:class], job_width)
        queue = truncate(job[:queue], 15)
        error = truncate(job[:error_class].to_s, error_width)
        failed_at = job[:failed_at]&.strftime("%Y-%m-%d %H:%M") || "N/A"

        row = sprintf("  %-#{job_width}s %-15s %-#{error_width}s %16s",
                      klass, queue, @pastel.red(error), failed_at)

        if actual_idx == selected
          lines << @pastel.black.on_white(row + " " * [width - visible_string_length(row), 0].max)
        else
          lines << row
        end
      end

      remaining = jobs.length - scroll_offset - data_rows
      if remaining > 0
        lines << @pastel.dim("  ↓ #{remaining} more")
      end

      # Status message
      if @status_message && @status_time && (Time.now - @status_time) < 3
        lines << @pastel.green("  #{@status_message}")
      end

      lines.join("\n")
    end

    def function_bar
      items = if @current_view == :main
        [
          ["q", "Queues"],
          ["p", "Procs"],
          ["w", "Workers"],
          ["r", "Retries"],
          ["s", "Sched"],
          ["d", "Dead"],
          ["^C", "Quit"]
        ]
      else
        [
          ["m", "Main"],
          ["q", "Queues"],
          ["p", "Procs"],
          ["w", "Workers"],
          ["r", "Retries"],
          ["s", "Sched"],
          ["d", "Dead"],
          ["^C", "Quit"]
        ]
      end

      bar = items.map do |key, label|
        @pastel.black.on_cyan.bold(key) + @pastel.white.on_blue(label)
      end.join(" ")

      width = terminal_width
      bar_len = visible_string_length(bar)
      padding = width - bar_len
      bar + @pastel.on_blue(" " * [padding, 0].max)
    end

    def format_number(num)
      num.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse
    end

    def format_latency(seconds)
      return "0s" if seconds.nil? || seconds == 0

      if seconds < 1
        "#{(seconds * 1000).round}ms"
      elsif seconds < 60
        "#{seconds.round(1)}s"
      elsif seconds < 3600
        "#{(seconds / 60).round(1)}m"
      else
        "#{(seconds / 3600).round(1)}h"
      end
    end

    def format_duration(seconds)
      return "0s" if seconds.nil? || seconds == 0

      if seconds < 60
        "#{seconds.round}s"
      elsif seconds < 3600
        mins = (seconds / 60).floor
        secs = (seconds % 60).round
        "#{mins}m#{secs}s"
      else
        hours = (seconds / 3600).floor
        mins = ((seconds % 3600) / 60).round
        "#{hours}h#{mins}m"
      end
    end

    def format_time_ago(time)
      seconds = Time.now - time
      if seconds < 60
        "now"
      elsif seconds < 3600
        "#{(seconds / 60).round}m"
      elsif seconds < 86400
        "#{(seconds / 3600).round}h"
      else
        "#{(seconds / 86400).round}d"
      end
    end

    def truncate(str, length)
      str = str.to_s
      str.length > length ? "#{str[0...length - 1]}~" : str
    end

    def terminal_size
      # Use TTY::Screen which handles raw mode and alternate screen better
      height = TTY::Screen.height
      width = TTY::Screen.width

      # Use cached value if TTY::Screen returns invalid size
      if height > 0 && width > 0
        @terminal_size = [height, width]
      elsif @terminal_size
        # Use previously cached size
      else
        # Fallback
        @terminal_size = [24, 80]
      end

      @terminal_size
    end

    def terminal_width
      terminal_size[1]
    end

    def terminal_height
      terminal_size[0]
    end
  end
end
