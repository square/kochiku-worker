require 'spec_helper'

describe BuildStrategy::BuildAllStrategy do
  let(:dev_null) { "2>/dev/null 1>/dev/null" }
  subject{ BuildStrategy::BuildAllStrategy.new }

  before do
    old_spawn = Process.method(:spawn)
    allow(Process).to receive(:spawn).and_return { |*args|
      @spawned_pid = old_spawn.call(*args)
    }
    File.unlink(BuildStrategy::BuildAllStrategy::LOG_FILE) if File.exists?(BuildStrategy::BuildAllStrategy::LOG_FILE)
  end

  describe "#execute_with_timeout" do
    let(:log) { IO.readlines(BuildStrategy::BuildAllStrategy::LOG_FILE) }

    it "should kill the command if it takes too long" do
      start_time = Time.now
      expect {
        subject.execute_with_timeout_and_kill("sleep 3 #{dev_null}", 0.1)
      }.to raise_error(Timeout::Error)
      expect(Time.now - start_time).to be_within(0.3).of(0.1)
      expect {
        Process.kill(0, @spawned_pid)
      }.to raise_error(Errno::ESRCH)

      expected = "******** Process taking too long, Kochiku killing it NOW ************\n"
      expect(log.last).to eq(expected)
    end

    it "should not claim to have killed when it didn't" do
      subject.execute_with_timeout_and_kill "true", 0.1

      expected = "******** Process taking too long, Kochiku killing it NOW ************\n"
      expect(log.last).not_to eq(expected)
    end

    it "should return true if it succeeds" do
      expect(subject.execute_with_timeout_and_kill("pwd #{dev_null}", 0.1)).to eq(true)
    end

    it "should return false if it fails" do
      expect(subject.execute_with_timeout_and_kill("ls /tmp/afilethatdoesnotexist #{dev_null}", 0.1)).to eq(false)
    end

    it "should raise a ErrorFoundInLogError for known errors in output" do
      expect {
        subject.execute_with_timeout_and_kill("echo 'couldn\'t find resque worker'", 0.1)
      }.to raise_error(BuildStrategy::BuildAllStrategy::ErrorFoundInLogError)
    end
  end

  describe "#child_processes" do
    it "only includes processes still running that are not this process or its parent" do
      Process.spawn("sleep 3")
      child_processes = subject.child_processes
      expect(child_processes).to include(@spawned_pid)
      expect(child_processes).not_to include(Process.pid)
      expect(child_processes).not_to include(Process.getpgrp)
    end
  end
end
