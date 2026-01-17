# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sktop::StatsCollector do
  let(:collector) { described_class.new }

  describe "#initialize" do
    it "creates a new stats collector" do
      expect(collector).to be_a(described_class)
    end
  end

  describe "#refresh!" do
    it "returns self for chaining" do
      expect(collector.refresh!).to eq(collector)
    end
  end

  describe "#overview" do
    before do
      stats = Sidekiq::Stats.new
      stats.processed = 1000
      stats.failed = 50
      stats.scheduled_size = 10
      stats.retry_size = 5
      stats.dead_size = 2
      stats.enqueued = 25
      stats.default_queue_latency = 0.5
      allow(Sidekiq::Stats).to receive(:new).and_return(stats)
      collector.refresh!
    end

    it "returns overview hash with all stats" do
      overview = collector.overview

      expect(overview).to be_a(Hash)
      expect(overview[:processed]).to eq(1000)
      expect(overview[:failed]).to eq(50)
      expect(overview[:scheduled_size]).to eq(10)
      expect(overview[:retry_size]).to eq(5)
      expect(overview[:dead_size]).to eq(2)
      expect(overview[:enqueued]).to eq(25)
      expect(overview[:default_queue_latency]).to eq(0.5)
    end
  end

  describe "#queues" do
    let(:queue1) { Sidekiq::Queue.new("default", 10, 0.1) }
    let(:queue2) { Sidekiq::Queue.new("critical", 5, 0.05) }

    before do
      allow(Sidekiq::Queue).to receive(:all).and_return([queue1, queue2])
    end

    it "returns array of queue hashes" do
      queues = collector.queues

      expect(queues).to be_an(Array)
      expect(queues.length).to eq(2)
    end

    it "includes queue details" do
      queues = collector.queues

      expect(queues.first[:name]).to eq("default")
      expect(queues.first[:size]).to eq(10)
      expect(queues.first[:latency]).to eq(0.1)
      expect(queues.first[:paused]).to eq(false)
    end
  end

  describe "#processes" do
    let(:process1) do
      Sidekiq::ProcessEntry.new(
        identity: "host1:1234:abc",
        hostname: "host1",
        pid: 1234,
        concurrency: 10,
        busy: 3,
        queues: ["default", "critical"],
        quiet: false,
        stopping: false,
        rss: 204800
      )
    end

    let(:process2) do
      Sidekiq::ProcessEntry.new(
        identity: "host2:5678:def",
        hostname: "host2",
        pid: 5678,
        concurrency: 20,
        busy: 15,
        queues: ["default"],
        quiet: true,
        stopping: false,
        rss: 409600
      )
    end

    before do
      allow(Sidekiq::ProcessSet).to receive(:new).and_return(
        Sidekiq::ProcessSet.new([process1, process2])
      )
    end

    it "returns array of process hashes" do
      processes = collector.processes

      expect(processes).to be_an(Array)
      expect(processes.length).to eq(2)
    end

    it "includes process details" do
      processes = collector.processes
      first = processes.first

      expect(first[:identity]).to eq("host1:1234:abc")
      expect(first[:hostname]).to eq("host1")
      expect(first[:pid]).to eq(1234)
      expect(first[:concurrency]).to eq(10)
      expect(first[:busy]).to eq(3)
      expect(first[:queues]).to eq(["default", "critical"])
      expect(first[:quiet]).to eq(false)
      expect(first[:stopping]).to eq(false)
      expect(first[:rss]).to eq(204800)
    end

    it "correctly detects quiet status" do
      processes = collector.processes

      expect(processes[0][:quiet]).to eq(false)
      expect(processes[1][:quiet]).to eq(true)
    end
  end

  describe "#workers" do
    let(:worker_data) do
      [
        ["host1:1234:abc", "thread1", {
          "queue" => "default",
          "payload" => { "class" => "TestJob", "args" => [1, 2] },
          "run_at" => Time.now.to_i - 30
        }],
        ["host1:1234:abc", "thread2", {
          "queue" => "critical",
          "payload" => { "class" => "ImportantJob", "args" => ["foo"] },
          "run_at" => Time.now.to_i - 120
        }]
      ]
    end

    before do
      workers = Sidekiq::Workers.new(worker_data)
      allow(Sidekiq::Workers).to receive(:new).and_return(workers)
    end

    it "returns array of worker hashes" do
      workers = collector.workers

      expect(workers).to be_an(Array)
      expect(workers.length).to eq(2)
    end

    it "includes worker details" do
      workers = collector.workers
      first = workers.first

      expect(first[:process_id]).to eq("host1:1234:abc")
      expect(first[:thread_id]).to eq("thread1")
      expect(first[:queue]).to eq("default")
      expect(first[:class]).to eq("TestJob")
      expect(first[:args]).to eq([1, 2])
      expect(first[:elapsed]).to be_within(1).of(30)
    end
  end

  describe "#scheduled_jobs" do
    let(:job1) do
      Sidekiq::JobEntry.new(
        jid: "abc123",
        klass: "ScheduledJob",
        queue: "default",
        args: [1],
        at: Time.now + 3600
      )
    end

    let(:job2) do
      Sidekiq::JobEntry.new(
        jid: "def456",
        klass: "AnotherJob",
        queue: "low",
        args: [],
        at: Time.now + 7200
      )
    end

    before do
      allow(Sidekiq::ScheduledSet).to receive(:new).and_return(
        Sidekiq::ScheduledSet.new([job1, job2])
      )
    end

    it "returns array of scheduled job hashes" do
      jobs = collector.scheduled_jobs

      expect(jobs).to be_an(Array)
      expect(jobs.length).to eq(2)
    end

    it "respects limit parameter" do
      jobs = collector.scheduled_jobs(limit: 1)

      expect(jobs.length).to eq(1)
    end

    it "includes job details" do
      jobs = collector.scheduled_jobs
      first = jobs.first

      expect(first[:class]).to eq("ScheduledJob")
      expect(first[:queue]).to eq("default")
      expect(first[:args]).to eq([1])
      expect(first[:scheduled_at]).to be_a(Time)
    end
  end

  describe "#retry_jobs" do
    let(:job) do
      Sidekiq::JobEntry.new(
        jid: "retry123",
        klass: "FailingJob",
        queue: "default",
        args: ["test"],
        data: {
          "failed_at" => Time.now.to_i - 3600,
          "retry_count" => 3,
          "error_class" => "StandardError",
          "error_message" => "Something went wrong"
        }
      )
    end

    before do
      allow(Sidekiq::RetrySet).to receive(:new).and_return(
        Sidekiq::RetrySet.new([job])
      )
    end

    it "returns array of retry job hashes" do
      jobs = collector.retry_jobs

      expect(jobs).to be_an(Array)
      expect(jobs.length).to eq(1)
    end

    it "includes retry-specific details" do
      jobs = collector.retry_jobs
      first = jobs.first

      expect(first[:jid]).to eq("retry123")
      expect(first[:class]).to eq("FailingJob")
      expect(first[:retry_count]).to eq(3)
      expect(first[:error_class]).to eq("StandardError")
      expect(first[:error_message]).to eq("Something went wrong")
    end
  end

  describe "#dead_jobs" do
    let(:job) do
      Sidekiq::JobEntry.new(
        jid: "dead123",
        klass: "DeadJob",
        queue: "default",
        args: [],
        data: {
          "failed_at" => Time.now.to_i - 86400,
          "error_class" => "FatalError",
          "error_message" => "Permanently failed"
        }
      )
    end

    before do
      allow(Sidekiq::DeadSet).to receive(:new).and_return(
        Sidekiq::DeadSet.new([job])
      )
    end

    it "returns array of dead job hashes" do
      jobs = collector.dead_jobs

      expect(jobs).to be_an(Array)
      expect(jobs.length).to eq(1)
    end

    it "includes dead job details" do
      jobs = collector.dead_jobs
      first = jobs.first

      expect(first[:jid]).to eq("dead123")
      expect(first[:class]).to eq("DeadJob")
      expect(first[:error_class]).to eq("FatalError")
    end
  end

  describe "#history" do
    it "returns history hash with processed and failed" do
      history = collector.history

      expect(history).to be_a(Hash)
      expect(history).to have_key(:processed)
      expect(history).to have_key(:failed)
    end

    it "accepts days parameter" do
      expect { collector.history(days: 14) }.not_to raise_error
    end
  end
end
