require 'spec_helper'

describe Kochiku::Worker::GitRepo do
  describe "#synchronize_with_remote" do
    it "should throw an exception after the third fetch attempt" do
      Kochiku::Worker.stub(:logger) { double('logger', :warn => nil) }
      fetch_double = double('git fetch')
      fetch_double.should_receive(:run).exactly(3).times.and_raise(Cocaine::ExitStatusError)
      Cocaine::CommandLine.stub(:new).with('git fetch', anything) { fetch_double }
      Kochiku::Worker::GitRepo.should_receive(:sleep).exactly(2).times

      expect { Kochiku::Worker::GitRepo.send(:synchronize_with_remote, "master") }.to raise_error(Cocaine::ExitStatusError)
    end
  end
end
