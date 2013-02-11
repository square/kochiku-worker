require 'spec_helper'

describe BuildStrategy::BuildAllStrategy do
  let(:dev_null) { "2>/dev/null 1>/dev/null" }
  subject{ BuildStrategy::BuildAllStrategy.new }

  before do
    old_spawn = Process.method(:spawn)
    Process.stub(:spawn).and_return do |*args|
      @spawned_pid = old_spawn.call(*args)
    end
  end

  describe "#execute_with_timeout" do
    let(:log) { IO.readlines(BuildStrategy::BuildAllStrategy::LOG_FILE) }

    it "should not block and kill command if it takes too long" do
      start_time = Time.now
      expect {
        subject.execute_with_timeout("sleep 3 #{dev_null}", 0.1).should == false
      }.to raise_error(Timeout::Error)
      (Time.now - start_time).should be_within(0.3).of(0.1)
      expect {
        Process.kill(0, @spawned_pid)
      }.to raise_error(Errno::ESRCH)

      expected = "******** Process taking too long, Kochiku killing it NOW ************\n"
      log.last.should == expected
    end

    it "should not claim to have killed when it didn't" do
      subject.execute_with_timeout "true", 0.1

      expected = "******** Process taking too long, Kochiku killing it NOW ************\n"
      log.last.should_not == expected
    end

    it "should return true if it succeeds" do
      subject.execute_with_timeout("pwd #{dev_null}", 0.1).should == true
    end

    it "should return false if it fails" do
      subject.execute_with_timeout("ls /tmp/afilethatdoesnotexist #{dev_null}", 0.1).should == false
    end
  end

  describe "#child_processes" do
    it "only includes processes still running that are not this process or its parent" do
      Process.spawn("sleep 3")
      child_processes = subject.child_processes
      child_processes.should include(@spawned_pid)
      child_processes.should_not include(Process.pid)
      child_processes.should_not include(Process.getpgrp)
    end
  end
end
