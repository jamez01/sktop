# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sktop::CLI do
  describe "#initialize" do
    it "sets default options" do
      cli = described_class.new([])

      options = cli.instance_variable_get(:@options)
      expect(options[:redis_url]).to eq("redis://localhost:6379/0")
      expect(options[:namespace]).to be_nil
      expect(options[:refresh_interval]).to eq(2)
      expect(options[:initial_view]).to eq(:main)
      expect(options[:once]).to eq(false)
    end

    it "uses REDIS_URL environment variable when set" do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("REDIS_URL").and_return("redis://custom:6380/1")

      cli = described_class.new([])
      options = cli.instance_variable_get(:@options)

      expect(options[:redis_url]).to eq("redis://custom:6380/1")
    end

    it "uses SIDEKIQ_NAMESPACE environment variable when set" do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("SIDEKIQ_NAMESPACE").and_return("myapp")

      cli = described_class.new([])
      options = cli.instance_variable_get(:@options)

      expect(options[:namespace]).to eq("myapp")
    end

    it "starts in running state" do
      cli = described_class.new([])
      expect(cli.instance_variable_get(:@running)).to eq(true)
    end
  end

  describe "option parsing" do
    describe "-r / --redis" do
      it "sets redis URL with short flag" do
        cli = described_class.new(["-r", "redis://other:6379/2"])
        cli.send(:parse_options!)

        options = cli.instance_variable_get(:@options)
        expect(options[:redis_url]).to eq("redis://other:6379/2")
      end

      it "sets redis URL with long flag" do
        cli = described_class.new(["--redis", "redis://long:6379/3"])
        cli.send(:parse_options!)

        options = cli.instance_variable_get(:@options)
        expect(options[:redis_url]).to eq("redis://long:6379/3")
      end
    end

    describe "-n / --namespace" do
      it "sets namespace with short flag" do
        cli = described_class.new(["-n", "production"])
        cli.send(:parse_options!)

        options = cli.instance_variable_get(:@options)
        expect(options[:namespace]).to eq("production")
      end

      it "sets namespace with long flag" do
        cli = described_class.new(["--namespace", "staging"])
        cli.send(:parse_options!)

        options = cli.instance_variable_get(:@options)
        expect(options[:namespace]).to eq("staging")
      end
    end

    describe "-i / --interval" do
      it "sets refresh interval with short flag" do
        cli = described_class.new(["-i", "5"])
        cli.send(:parse_options!)

        options = cli.instance_variable_get(:@options)
        expect(options[:refresh_interval]).to eq(5)
      end

      it "sets refresh interval with long flag" do
        cli = described_class.new(["--interval", "10"])
        cli.send(:parse_options!)

        options = cli.instance_variable_get(:@options)
        expect(options[:refresh_interval]).to eq(10)
      end
    end

    describe "-1 / --once" do
      it "sets once mode with short flag" do
        cli = described_class.new(["-1"])
        cli.send(:parse_options!)

        options = cli.instance_variable_get(:@options)
        expect(options[:once]).to eq(true)
      end

      it "sets once mode with long flag" do
        cli = described_class.new(["--once"])
        cli.send(:parse_options!)

        options = cli.instance_variable_get(:@options)
        expect(options[:once]).to eq(true)
      end
    end

    describe "view flags" do
      it "sets initial view to main with -m" do
        cli = described_class.new(["-m"])
        cli.send(:parse_options!)

        options = cli.instance_variable_get(:@options)
        expect(options[:initial_view]).to eq(:main)
      end

      it "sets initial view to main with --main" do
        cli = described_class.new(["--main"])
        cli.send(:parse_options!)

        options = cli.instance_variable_get(:@options)
        expect(options[:initial_view]).to eq(:main)
      end

      it "sets initial view to queues with -q" do
        cli = described_class.new(["-q"])
        cli.send(:parse_options!)

        options = cli.instance_variable_get(:@options)
        expect(options[:initial_view]).to eq(:queues)
      end

      it "sets initial view to queues with --queues" do
        cli = described_class.new(["--queues"])
        cli.send(:parse_options!)

        options = cli.instance_variable_get(:@options)
        expect(options[:initial_view]).to eq(:queues)
      end

      it "sets initial view to processes with -p" do
        cli = described_class.new(["-p"])
        cli.send(:parse_options!)

        options = cli.instance_variable_get(:@options)
        expect(options[:initial_view]).to eq(:processes)
      end

      it "sets initial view to processes with --processes" do
        cli = described_class.new(["--processes"])
        cli.send(:parse_options!)

        options = cli.instance_variable_get(:@options)
        expect(options[:initial_view]).to eq(:processes)
      end

      it "sets initial view to workers with -w" do
        cli = described_class.new(["-w"])
        cli.send(:parse_options!)

        options = cli.instance_variable_get(:@options)
        expect(options[:initial_view]).to eq(:workers)
      end

      it "sets initial view to workers with --workers" do
        cli = described_class.new(["--workers"])
        cli.send(:parse_options!)

        options = cli.instance_variable_get(:@options)
        expect(options[:initial_view]).to eq(:workers)
      end

      it "sets initial view to retries with -R" do
        cli = described_class.new(["-R"])
        cli.send(:parse_options!)

        options = cli.instance_variable_get(:@options)
        expect(options[:initial_view]).to eq(:retries)
      end

      it "sets initial view to retries with --retries" do
        cli = described_class.new(["--retries"])
        cli.send(:parse_options!)

        options = cli.instance_variable_get(:@options)
        expect(options[:initial_view]).to eq(:retries)
      end

      it "sets initial view to scheduled with -s" do
        cli = described_class.new(["-s"])
        cli.send(:parse_options!)

        options = cli.instance_variable_get(:@options)
        expect(options[:initial_view]).to eq(:scheduled)
      end

      it "sets initial view to scheduled with --scheduled" do
        cli = described_class.new(["--scheduled"])
        cli.send(:parse_options!)

        options = cli.instance_variable_get(:@options)
        expect(options[:initial_view]).to eq(:scheduled)
      end

      it "sets initial view to dead with -d" do
        cli = described_class.new(["-d"])
        cli.send(:parse_options!)

        options = cli.instance_variable_get(:@options)
        expect(options[:initial_view]).to eq(:dead)
      end

      it "sets initial view to dead with --dead" do
        cli = described_class.new(["--dead"])
        cli.send(:parse_options!)

        options = cli.instance_variable_get(:@options)
        expect(options[:initial_view]).to eq(:dead)
      end
    end

    describe "-v / --version" do
      it "prints version and exits" do
        cli = described_class.new(["-v"])

        expect {
          cli.send(:parse_options!)
        }.to raise_error(SystemExit).and output(/sktop/).to_stdout
      end

      it "prints version with long flag" do
        cli = described_class.new(["--version"])

        expect {
          cli.send(:parse_options!)
        }.to raise_error(SystemExit).and output(/sktop/).to_stdout
      end
    end

    describe "-h / --help" do
      it "prints help and exits" do
        cli = described_class.new(["-h"])

        expect {
          cli.send(:parse_options!)
        }.to raise_error(SystemExit).and output(/Usage:/).to_stdout
      end

      it "prints help with long flag" do
        cli = described_class.new(["--help"])

        expect {
          cli.send(:parse_options!)
        }.to raise_error(SystemExit).and output(/Usage:/).to_stdout
      end
    end

    describe "combined options" do
      it "handles multiple flags together" do
        cli = described_class.new(["-r", "redis://host:6379/0", "-n", "app", "-i", "5", "-w", "-1"])
        cli.send(:parse_options!)

        options = cli.instance_variable_get(:@options)
        expect(options[:redis_url]).to eq("redis://host:6379/0")
        expect(options[:namespace]).to eq("app")
        expect(options[:refresh_interval]).to eq(5)
        expect(options[:initial_view]).to eq(:workers)
        expect(options[:once]).to eq(true)
      end

      it "uses the last view flag when multiple are provided" do
        cli = described_class.new(["-q", "-p", "-w"])
        cli.send(:parse_options!)

        options = cli.instance_variable_get(:@options)
        expect(options[:initial_view]).to eq(:workers)
      end
    end
  end

  describe "#shutdown" do
    it "sets running to false" do
      cli = described_class.new([])
      cli.shutdown

      expect(cli.instance_variable_get(:@running)).to eq(false)
    end

    it "outputs terminal escape sequences" do
      cli = described_class.new([])

      expect {
        cli.shutdown
      }.to output(/\e\[\?25h/).to_stdout
    end
  end

  describe "#handle_keypress" do
    let(:cli) { described_class.new([]) }
    let(:display) { instance_double(Sktop::Display) }
    let(:stdin) { double("stdin") }

    before do
      cli.instance_variable_set(:@display, display)
      cli.instance_variable_set(:@data_mutex, Mutex.new)
      cli.instance_variable_set(:@cached_data, nil)
      allow(display).to receive(:current_view=)
      allow(display).to receive(:current_view).and_return(:main)
      allow(display).to receive(:selected_index).and_return(0)
      allow(display).to receive(:select_up)
      allow(display).to receive(:select_down)
      allow(display).to receive(:page_up)
      allow(display).to receive(:page_down)
      allow(display).to receive(:set_status)
    end

    it "switches to queues view on 'q'" do
      expect(display).to receive(:current_view=).with(:queues)
      cli.send(:handle_keypress, "q", stdin)
    end

    it "switches to queues view on 'Q'" do
      expect(display).to receive(:current_view=).with(:queues)
      cli.send(:handle_keypress, "Q", stdin)
    end

    it "switches to processes view on 'p'" do
      expect(display).to receive(:current_view=).with(:processes)
      cli.send(:handle_keypress, "p", stdin)
    end

    it "switches to workers view on 'w'" do
      expect(display).to receive(:current_view=).with(:workers)
      cli.send(:handle_keypress, "w", stdin)
    end

    it "switches to retries view on 'r'" do
      expect(display).to receive(:current_view=).with(:retries)
      cli.send(:handle_keypress, "r", stdin)
    end

    it "switches to scheduled view on 's'" do
      expect(display).to receive(:current_view=).with(:scheduled)
      cli.send(:handle_keypress, "s", stdin)
    end

    it "switches to dead view on 'd'" do
      expect(display).to receive(:current_view=).with(:dead)
      cli.send(:handle_keypress, "d", stdin)
    end

    it "switches to main view on 'm'" do
      expect(display).to receive(:current_view=).with(:main)
      cli.send(:handle_keypress, "m", stdin)
    end

    it "raises Interrupt on Ctrl+C" do
      expect {
        cli.send(:handle_keypress, "\u0003", stdin)
      }.to raise_error(Interrupt)
    end

    context "with escape sequences" do
      it "calls select_up on up arrow" do
        allow(IO).to receive(:select).and_return([[stdin], nil, nil])
        allow(stdin).to receive(:read_nonblock).and_return("[A")

        expect(display).to receive(:select_up)
        cli.send(:handle_keypress, "\e", stdin)
      end

      it "calls select_down on down arrow" do
        allow(IO).to receive(:select).and_return([[stdin], nil, nil])
        allow(stdin).to receive(:read_nonblock).and_return("[B")

        expect(display).to receive(:select_down)
        cli.send(:handle_keypress, "\e", stdin)
      end

      it "calls page_up on Page Up" do
        allow(IO).to receive(:select).and_return([[stdin], nil, nil])
        allow(stdin).to receive(:read_nonblock).and_return("[5~")

        expect(display).to receive(:page_up)
        cli.send(:handle_keypress, "\e", stdin)
      end

      it "calls page_down on Page Down" do
        allow(IO).to receive(:select).and_return([[stdin], nil, nil])
        allow(stdin).to receive(:read_nonblock).and_return("[6~")

        expect(display).to receive(:page_down)
        cli.send(:handle_keypress, "\e", stdin)
      end

      it "switches to main view on plain Escape" do
        allow(IO).to receive(:select).and_return(nil)

        expect(display).to receive(:current_view=).with(:main)
        cli.send(:handle_keypress, "\e", stdin)
      end
    end
  end

  describe "#handle_retry_action" do
    let(:cli) { described_class.new([]) }
    let(:display) { instance_double(Sktop::Display) }

    before do
      cli.instance_variable_set(:@display, display)
      cli.instance_variable_set(:@data_mutex, Mutex.new)
      cli.instance_variable_set(:@rendered_version, 0)
      allow(display).to receive(:set_status)
    end

    context "when not in retries or dead view" do
      it "does nothing" do
        allow(display).to receive(:current_view).and_return(:main)

        expect(Sktop::JobActions).not_to receive(:retry_job)
        cli.send(:handle_retry_action)
      end
    end

    context "when no cached data" do
      it "sets error status" do
        allow(display).to receive(:current_view).and_return(:retries)
        cli.instance_variable_set(:@cached_data, nil)

        expect(display).to receive(:set_status).with("No data available")
        cli.send(:handle_retry_action)
      end
    end

    context "when jobs exist" do
      let(:cached_data) do
        {
          retry_jobs: [{ jid: "test123", class: "TestJob" }]
        }
      end

      before do
        cli.instance_variable_set(:@cached_data, cached_data)
        allow(display).to receive(:current_view).and_return(:retries)
        allow(display).to receive(:selected_index).and_return(0)
      end

      it "retries the selected job" do
        expect(Sktop::JobActions).to receive(:retry_job).with("test123", :retry)
        expect(display).to receive(:set_status).with("Retrying TestJob")

        cli.send(:handle_retry_action)
      end
    end
  end

  describe "#handle_delete_action" do
    let(:cli) { described_class.new([]) }
    let(:display) { instance_double(Sktop::Display) }

    before do
      cli.instance_variable_set(:@display, display)
      cli.instance_variable_set(:@data_mutex, Mutex.new)
      cli.instance_variable_set(:@rendered_version, 0)
      allow(display).to receive(:set_status)
    end

    context "when jobs exist" do
      let(:cached_data) do
        {
          dead_jobs: [{ jid: "dead123", class: "DeadJob" }]
        }
      end

      before do
        cli.instance_variable_set(:@cached_data, cached_data)
        allow(display).to receive(:current_view).and_return(:dead)
        allow(display).to receive(:selected_index).and_return(0)
      end

      it "deletes the selected job" do
        expect(Sktop::JobActions).to receive(:delete_job).with("dead123", :dead)
        expect(display).to receive(:set_status).with("Deleted DeadJob")

        cli.send(:handle_delete_action)
      end
    end
  end

  describe "#handle_quiet_process_action" do
    let(:cli) { described_class.new([]) }
    let(:display) { instance_double(Sktop::Display) }

    before do
      cli.instance_variable_set(:@display, display)
      cli.instance_variable_set(:@data_mutex, Mutex.new)
      cli.instance_variable_set(:@rendered_version, 0)
      allow(display).to receive(:set_status)
    end

    context "when not in processes view" do
      it "does nothing" do
        allow(display).to receive(:current_view).and_return(:main)

        expect(Sktop::JobActions).not_to receive(:quiet_process)
        cli.send(:handle_quiet_process_action)
      end
    end

    context "when process exists" do
      let(:cached_data) do
        {
          processes: [{ identity: "host:1234:abc", hostname: "host", pid: 1234 }]
        }
      end

      before do
        cli.instance_variable_set(:@cached_data, cached_data)
        allow(display).to receive(:current_view).and_return(:processes)
        allow(display).to receive(:selected_index).and_return(0)
      end

      it "quiets the selected process" do
        expect(Sktop::JobActions).to receive(:quiet_process).with("host:1234:abc")
        expect(display).to receive(:set_status).with("Quieting host:1234")

        cli.send(:handle_quiet_process_action)
      end
    end
  end

  describe "#handle_stop_process_action" do
    let(:cli) { described_class.new([]) }
    let(:display) { instance_double(Sktop::Display) }

    before do
      cli.instance_variable_set(:@display, display)
      cli.instance_variable_set(:@data_mutex, Mutex.new)
      cli.instance_variable_set(:@rendered_version, 0)
      allow(display).to receive(:set_status)
    end

    context "when process exists" do
      let(:cached_data) do
        {
          processes: [{ identity: "host:5678:def", hostname: "host", pid: 5678 }]
        }
      end

      before do
        cli.instance_variable_set(:@cached_data, cached_data)
        allow(display).to receive(:current_view).and_return(:processes)
        allow(display).to receive(:selected_index).and_return(0)
      end

      it "stops the selected process" do
        expect(Sktop::JobActions).to receive(:stop_process).with("host:5678:def")
        expect(display).to receive(:set_status).with("Stopping host:5678")

        cli.send(:handle_stop_process_action)
      end
    end
  end

  describe "#handle_retry_all_action" do
    let(:cli) { described_class.new([]) }
    let(:display) { instance_double(Sktop::Display) }

    before do
      cli.instance_variable_set(:@display, display)
      cli.instance_variable_set(:@rendered_version, 0)
      allow(display).to receive(:set_status)
    end

    context "when in retries view" do
      before do
        allow(display).to receive(:current_view).and_return(:retries)
      end

      it "retries all jobs" do
        expect(Sktop::JobActions).to receive(:retry_all).with(:retry).and_return(5)
        expect(display).to receive(:set_status).with("Retrying all 5 jobs")

        cli.send(:handle_retry_all_action)
      end
    end

    context "when not in retries or dead view" do
      it "does nothing" do
        allow(display).to receive(:current_view).and_return(:main)

        expect(Sktop::JobActions).not_to receive(:retry_all)
        cli.send(:handle_retry_all_action)
      end
    end
  end

  describe "#handle_delete_all_action" do
    let(:cli) { described_class.new([]) }
    let(:display) { instance_double(Sktop::Display) }

    before do
      cli.instance_variable_set(:@display, display)
      cli.instance_variable_set(:@rendered_version, 0)
      allow(display).to receive(:set_status)
    end

    context "when in dead view" do
      before do
        allow(display).to receive(:current_view).and_return(:dead)
      end

      it "deletes all jobs" do
        expect(Sktop::JobActions).to receive(:delete_all).with(:dead).and_return(10)
        expect(display).to receive(:set_status).with("Deleted all 10 jobs")

        cli.send(:handle_delete_all_action)
      end
    end
  end
end
