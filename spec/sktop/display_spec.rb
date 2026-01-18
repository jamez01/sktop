# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sktop::Display do
  let(:display) { described_class.new }

  before do
    # Mock terminal size
    allow(TTY::Screen).to receive(:height).and_return(24)
    allow(TTY::Screen).to receive(:width).and_return(80)
  end

  describe "#initialize" do
    it "sets default view to :main" do
      expect(display.current_view).to eq(:main)
    end
  end

  describe "#current_view=" do
    it "changes the current view" do
      display.current_view = :queues
      expect(display.current_view).to eq(:queues)
    end

    it "preserves scroll position when switching views" do
      display.current_view = :queues
      display.scroll_down
      display.scroll_down
      display.current_view = :processes
      display.current_view = :queues

      # Scroll offset should be preserved
      expect(display.instance_variable_get(:@scroll_offsets)[:queues]).to eq(2)
    end
  end

  describe "scrolling" do
    describe "#scroll_up" do
      it "decreases scroll offset" do
        display.current_view = :queues
        display.scroll_down
        display.scroll_down
        display.scroll_up

        expect(display.instance_variable_get(:@scroll_offsets)[:queues]).to eq(1)
      end

      it "does not go below zero" do
        display.current_view = :queues
        display.scroll_up
        display.scroll_up

        expect(display.instance_variable_get(:@scroll_offsets)[:queues]).to eq(0)
      end
    end

    describe "#scroll_down" do
      it "increases scroll offset" do
        display.current_view = :queues
        display.scroll_down

        expect(display.instance_variable_get(:@scroll_offsets)[:queues]).to eq(1)
      end
    end

    describe "#reset_scroll" do
      it "resets scroll offset to zero" do
        display.current_view = :queues
        display.scroll_down
        display.scroll_down
        display.reset_scroll

        expect(display.instance_variable_get(:@scroll_offsets)[:queues]).to eq(0)
      end
    end
  end

  describe "selection" do
    describe "#select_up" do
      context "in selectable view" do
        before { display.current_view = :processes }

        it "decreases selected index" do
          display.select_down
          display.select_down
          display.select_up

          expect(display.selected_index).to eq(1)
        end

        it "does not go below zero" do
          display.select_up
          display.select_up

          expect(display.selected_index).to eq(0)
        end
      end

      context "in non-selectable view" do
        before { display.current_view = :scheduled }

        it "scrolls instead of selecting" do
          display.scroll_down
          display.scroll_down
          display.select_up

          expect(display.instance_variable_get(:@scroll_offsets)[:scheduled]).to eq(1)
        end
      end
    end

    describe "#select_down" do
      context "in selectable view" do
        before { display.current_view = :retries }

        it "increases selected index" do
          display.select_down

          expect(display.selected_index).to eq(1)
        end
      end

      context "in non-selectable view" do
        before { display.current_view = :workers }

        it "scrolls instead of selecting" do
          display.select_down

          expect(display.instance_variable_get(:@scroll_offsets)[:workers]).to eq(1)
        end
      end
    end

    describe "#selected_index" do
      it "returns the selected index for the current view" do
        display.current_view = :dead
        display.select_down
        display.select_down

        expect(display.selected_index).to eq(2)
      end

      it "maintains separate indices per view" do
        display.current_view = :retries
        display.select_down
        display.select_down

        display.current_view = :dead
        display.select_down

        expect(display.selected_index).to eq(1)

        display.current_view = :retries
        expect(display.selected_index).to eq(2)
      end
    end
  end

  describe "paging" do
    describe "#page_up" do
      context "in selectable view" do
        before { display.current_view = :processes }

        it "moves selection up by page size" do
          20.times { display.select_down }
          display.page_up

          # Page size is terminal_height - 8, so ~16 on a 24-line terminal
          expect(display.selected_index).to be < 10
        end
      end

      context "in non-selectable view" do
        before { display.current_view = :scheduled }

        it "scrolls up by page size" do
          20.times { display.scroll_down }
          display.page_up

          expect(display.instance_variable_get(:@scroll_offsets)[:scheduled]).to be < 10
        end
      end
    end

    describe "#page_down" do
      context "in selectable view" do
        before { display.current_view = :dead }

        it "moves selection down by page size" do
          display.page_down

          expect(display.selected_index).to be > 10
        end
      end
    end

    describe "#default_page_size" do
      it "returns terminal height minus overhead" do
        expect(display.send(:default_page_size)).to eq(16) # 24 - 8
      end

      it "has a minimum of 5" do
        allow(TTY::Screen).to receive(:height).and_return(10)
        display.update_terminal_size

        expect(display.send(:default_page_size)).to eq(5)
      end
    end
  end

  describe "#selectable_view?" do
    it "returns true for processes view" do
      display.current_view = :processes
      expect(display.send(:selectable_view?)).to eq(true)
    end

    it "returns true for retries view" do
      display.current_view = :retries
      expect(display.send(:selectable_view?)).to eq(true)
    end

    it "returns true for dead view" do
      display.current_view = :dead
      expect(display.send(:selectable_view?)).to eq(true)
    end

    it "returns true for queues view" do
      display.current_view = :queues
      expect(display.send(:selectable_view?)).to eq(true)
    end

    it "returns false for workers view" do
      display.current_view = :workers
      expect(display.send(:selectable_view?)).to eq(false)
    end

    it "returns false for scheduled view" do
      display.current_view = :scheduled
      expect(display.send(:selectable_view?)).to eq(false)
    end
  end

  describe "#set_status" do
    it "sets the status message" do
      display.set_status("Test message")

      expect(display.instance_variable_get(:@status_message)).to eq("Test message")
    end

    it "sets the status time" do
      freeze_time = Time.now
      allow(Time).to receive(:now).and_return(freeze_time)

      display.set_status("Test")

      expect(display.instance_variable_get(:@status_time)).to eq(freeze_time)
    end
  end

  describe "#update_terminal_size" do
    it "updates cached terminal size" do
      allow(TTY::Screen).to receive(:height).and_return(50)
      allow(TTY::Screen).to receive(:width).and_return(120)

      display.update_terminal_size

      expect(display.send(:terminal_height)).to eq(50)
      expect(display.send(:terminal_width)).to eq(120)
    end
  end

  describe "formatting helpers" do
    describe "#format_number" do
      it "formats numbers with thousands separators" do
        expect(display.send(:format_number, 1000)).to eq("1,000")
        expect(display.send(:format_number, 1000000)).to eq("1,000,000")
        expect(display.send(:format_number, 123)).to eq("123")
      end
    end

    describe "#format_latency" do
      it "formats milliseconds" do
        expect(display.send(:format_latency, 0.5)).to eq("500ms")
      end

      it "formats seconds" do
        expect(display.send(:format_latency, 5.5)).to eq("5.5s")
      end

      it "formats minutes" do
        expect(display.send(:format_latency, 120)).to eq("2m")
      end

      it "formats hours" do
        expect(display.send(:format_latency, 7200)).to eq("2h")
      end

      it "handles zero" do
        expect(display.send(:format_latency, 0)).to eq("0s")
      end

      it "handles nil" do
        expect(display.send(:format_latency, nil)).to eq("0s")
      end
    end

    describe "#format_duration" do
      it "formats seconds" do
        expect(display.send(:format_duration, 45)).to eq("45s")
      end

      it "formats minutes and seconds" do
        expect(display.send(:format_duration, 125)).to eq("2m5s")
      end

      it "formats hours and minutes" do
        expect(display.send(:format_duration, 3725)).to eq("1h2m")
      end
    end

    describe "#format_time_ago" do
      it "returns 'now' for recent times" do
        expect(display.send(:format_time_ago, Time.now - 30)).to eq("now")
      end

      it "returns minutes" do
        expect(display.send(:format_time_ago, Time.now - 300)).to eq("5m")
      end

      it "returns hours" do
        expect(display.send(:format_time_ago, Time.now - 7200)).to eq("2h")
      end

      it "returns days" do
        expect(display.send(:format_time_ago, Time.now - 172800)).to eq("2d")
      end
    end

    describe "#format_memory" do
      it "formats kilobytes" do
        expect(display.send(:format_memory, 512)).to eq("512K")
      end

      it "formats megabytes" do
        expect(display.send(:format_memory, 102400)).to eq("100.0M")
      end

      it "formats gigabytes" do
        expect(display.send(:format_memory, 2097152)).to eq("2.0G")
      end

      it "handles nil" do
        expect(display.send(:format_memory, nil)).to eq("N/A")
      end

      it "handles zero" do
        expect(display.send(:format_memory, 0)).to eq("N/A")
      end
    end

    describe "#truncate" do
      it "truncates long strings" do
        expect(display.send(:truncate, "This is a very long string", 10)).to eq("This is a~")
      end

      it "leaves short strings unchanged" do
        expect(display.send(:truncate, "Short", 10)).to eq("Short")
      end
    end

    describe "#visible_string_length" do
      it "calculates length ignoring ANSI codes" do
        str = "\e[31mRed\e[0m"
        expect(display.send(:visible_string_length, str)).to eq(3)
      end

      it "handles strings without ANSI codes" do
        expect(display.send(:visible_string_length, "Normal")).to eq(6)
      end
    end
  end

  describe "#render" do
    let(:mock_collector) { double("collector") }

    before do
      allow(mock_collector).to receive(:overview).and_return({
        processed: 1000,
        failed: 10,
        scheduled_size: 5,
        retry_size: 3,
        dead_size: 1,
        enqueued: 20,
        default_queue_latency: 0.5
      })
      allow(mock_collector).to receive(:queues).and_return([])
      allow(mock_collector).to receive(:processes).and_return([])
      allow(mock_collector).to receive(:workers).and_return([])
      allow(mock_collector).to receive(:retry_jobs).and_return([])
      allow(mock_collector).to receive(:scheduled_jobs).and_return([])
      allow(mock_collector).to receive(:dead_jobs).and_return([])
    end

    it "returns a string" do
      result = display.render(mock_collector)
      expect(result).to be_a(String)
    end

    it "includes the header" do
      result = display.render(mock_collector)
      expect(result).to include("sktop")
    end

    context "for different views" do
      it "renders main view" do
        display.current_view = :main
        result = display.render(mock_collector)
        expect(result).to include("Processes")
        expect(result).to include("Workers")
      end

      it "renders queues view" do
        display.current_view = :queues
        result = display.render(mock_collector)
        expect(result).to include("Queues")
      end

      it "renders processes view" do
        display.current_view = :processes
        result = display.render(mock_collector)
        expect(result).to include("Processes")
      end

      it "renders workers view" do
        display.current_view = :workers
        result = display.render(mock_collector)
        expect(result).to include("Workers")
      end

      it "renders retries view" do
        display.current_view = :retries
        result = display.render(mock_collector)
        expect(result).to include("Retry")
      end

      it "renders scheduled view" do
        display.current_view = :scheduled
        result = display.render(mock_collector)
        expect(result).to include("Scheduled")
      end

      it "renders dead view" do
        display.current_view = :dead
        result = display.render(mock_collector)
        expect(result).to include("Dead")
      end
    end
  end

  describe Sktop::Display::CachedData do
    let(:data) do
      {
        overview: { processed: 100 },
        queues: [{ name: "default" }],
        processes: [{ hostname: "host1" }],
        workers: [{ class: "TestJob" }],
        retry_jobs: [{ jid: "r1" }, { jid: "r2" }],
        scheduled_jobs: [{ jid: "s1" }],
        dead_jobs: [{ jid: "d1" }]
      }
    end

    let(:cached) { described_class.new(data) }

    it "returns overview" do
      expect(cached.overview[:processed]).to eq(100)
    end

    it "returns queues" do
      expect(cached.queues.first[:name]).to eq("default")
    end

    it "returns processes" do
      expect(cached.processes.first[:hostname]).to eq("host1")
    end

    it "returns workers" do
      expect(cached.workers.first[:class]).to eq("TestJob")
    end

    it "returns retry_jobs with limit" do
      expect(cached.retry_jobs(limit: 1).length).to eq(1)
    end

    it "returns scheduled_jobs with limit" do
      expect(cached.scheduled_jobs(limit: 1).length).to eq(1)
    end

    it "returns dead_jobs with limit" do
      expect(cached.dead_jobs(limit: 1).length).to eq(1)
    end

    it "handles nil data gracefully" do
      empty_cached = described_class.new({})
      expect(empty_cached.retry_jobs).to eq([])
    end
  end
end
