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
    it "should not block and kill command if it takes too long" do
      start_time = Time.now
      subject.execute_with_timeout("sleep 3 #{dev_null}", 0.1).should == false
      (Time.now - start_time).should be_within(0.3).of(0.1)
      expect {
        Process.kill(0, @spawned_pid)
      }.to raise_error(Errno::ESRCH)
    end

    it "should return true if it succeeds" do
      start_time = Time.now
      subject.execute_with_timeout("pwd #{dev_null}", 0.1).should == true
    end
  end
end
