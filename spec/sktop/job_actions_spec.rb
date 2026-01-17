# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sktop::JobActions do
  describe ".retry_job" do
    let(:job) do
      Sidekiq::JobEntry.new(jid: "test123", klass: "TestJob")
    end

    context "when job exists in retry set" do
      before do
        retry_set = Sidekiq::RetrySet.new([job])
        allow(Sidekiq::RetrySet).to receive(:new).and_return(retry_set)
      end

      it "retries the job" do
        expect(job).to receive(:retry)
        described_class.retry_job("test123", :retry)
      end

      it "returns true on success" do
        expect(described_class.retry_job("test123", :retry)).to eq(true)
      end
    end

    context "when job exists in dead set" do
      before do
        dead_set = Sidekiq::DeadSet.new([job])
        allow(Sidekiq::DeadSet).to receive(:new).and_return(dead_set)
      end

      it "retries the job from dead set" do
        expect(job).to receive(:retry)
        described_class.retry_job("test123", :dead)
      end
    end

    context "when job does not exist" do
      before do
        allow(Sidekiq::RetrySet).to receive(:new).and_return(Sidekiq::RetrySet.new([]))
      end

      it "raises an error" do
        expect {
          described_class.retry_job("nonexistent", :retry)
        }.to raise_error(RuntimeError, /Job not found/)
      end
    end
  end

  describe ".delete_job" do
    let(:job) do
      Sidekiq::JobEntry.new(jid: "delete123", klass: "TestJob")
    end

    context "when job exists" do
      before do
        retry_set = Sidekiq::RetrySet.new([job])
        allow(Sidekiq::RetrySet).to receive(:new).and_return(retry_set)
      end

      it "deletes the job" do
        expect(job).to receive(:delete)
        described_class.delete_job("delete123", :retry)
      end

      it "returns true on success" do
        expect(described_class.delete_job("delete123", :retry)).to eq(true)
      end
    end

    context "when job does not exist" do
      before do
        allow(Sidekiq::RetrySet).to receive(:new).and_return(Sidekiq::RetrySet.new([]))
      end

      it "raises an error" do
        expect {
          described_class.delete_job("nonexistent", :retry)
        }.to raise_error(RuntimeError, /Job not found/)
      end
    end
  end

  describe ".kill_job" do
    let(:job) do
      Sidekiq::JobEntry.new(jid: "kill123", klass: "TestJob")
    end

    context "when job exists" do
      before do
        retry_set = Sidekiq::RetrySet.new([job])
        allow(Sidekiq::RetrySet).to receive(:new).and_return(retry_set)
      end

      it "kills the job" do
        expect(job).to receive(:kill)
        described_class.kill_job("kill123", :retry)
      end

      it "returns true on success" do
        expect(described_class.kill_job("kill123", :retry)).to eq(true)
      end
    end
  end

  describe ".retry_all" do
    let(:jobs) do
      [
        Sidekiq::JobEntry.new(jid: "job1"),
        Sidekiq::JobEntry.new(jid: "job2"),
        Sidekiq::JobEntry.new(jid: "job3")
      ]
    end

    before do
      retry_set = Sidekiq::RetrySet.new(jobs)
      allow(Sidekiq::RetrySet).to receive(:new).and_return(retry_set)
    end

    it "returns the count of jobs retried" do
      expect(described_class.retry_all(:retry)).to eq(3)
    end
  end

  describe ".delete_all" do
    let(:jobs) do
      [
        Sidekiq::JobEntry.new(jid: "job1"),
        Sidekiq::JobEntry.new(jid: "job2")
      ]
    end

    before do
      dead_set = Sidekiq::DeadSet.new(jobs)
      allow(Sidekiq::DeadSet).to receive(:new).and_return(dead_set)
    end

    it "returns the count of jobs deleted" do
      expect(described_class.delete_all(:dead)).to eq(2)
    end
  end

  describe ".quiet_process" do
    let(:process) do
      Sidekiq::ProcessEntry.new(identity: "host:1234:abc", hostname: "host")
    end

    context "when process exists" do
      before do
        process_set = Sidekiq::ProcessSet.new([process])
        allow(Sidekiq::ProcessSet).to receive(:new).and_return(process_set)
      end

      it "quiets the process" do
        expect(process).to receive(:quiet!)
        described_class.quiet_process("host:1234:abc")
      end

      it "returns true on success" do
        expect(described_class.quiet_process("host:1234:abc")).to eq(true)
      end
    end

    context "when process does not exist" do
      before do
        allow(Sidekiq::ProcessSet).to receive(:new).and_return(Sidekiq::ProcessSet.new([]))
      end

      it "raises an error" do
        expect {
          described_class.quiet_process("nonexistent")
        }.to raise_error(RuntimeError, /Process not found/)
      end
    end
  end

  describe ".stop_process" do
    let(:process) do
      Sidekiq::ProcessEntry.new(identity: "host:5678:def", hostname: "host")
    end

    context "when process exists" do
      before do
        process_set = Sidekiq::ProcessSet.new([process])
        allow(Sidekiq::ProcessSet).to receive(:new).and_return(process_set)
      end

      it "stops the process" do
        expect(process).to receive(:stop!)
        described_class.stop_process("host:5678:def")
      end

      it "returns true on success" do
        expect(described_class.stop_process("host:5678:def")).to eq(true)
      end
    end

    context "when process does not exist" do
      before do
        allow(Sidekiq::ProcessSet).to receive(:new).and_return(Sidekiq::ProcessSet.new([]))
      end

      it "raises an error" do
        expect {
          described_class.stop_process("nonexistent")
        }.to raise_error(RuntimeError, /Process not found/)
      end
    end
  end

  describe "source parameter handling" do
    it "accepts :retry source" do
      allow(Sidekiq::RetrySet).to receive(:new).and_return(Sidekiq::RetrySet.new([]))
      expect { described_class.retry_all(:retry) }.not_to raise_error
    end

    it "accepts :dead source" do
      allow(Sidekiq::DeadSet).to receive(:new).and_return(Sidekiq::DeadSet.new([]))
      expect { described_class.retry_all(:dead) }.not_to raise_error
    end

    it "accepts :scheduled source" do
      allow(Sidekiq::ScheduledSet).to receive(:new).and_return(Sidekiq::ScheduledSet.new([]))
      expect { described_class.delete_all(:scheduled) }.not_to raise_error
    end

    it "raises error for unknown source" do
      expect {
        described_class.retry_all(:invalid)
      }.to raise_error(RuntimeError, /Unknown source/)
    end
  end
end
