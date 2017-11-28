require 'spec_helper'

RSpec.describe GitStrategy::LocalCache do
  describe "#run_git_fetch" do
    before do
      Retryable.configure do |config|
        config.sleep_method = Proc.new { } # do nothing
      end
      Retryable.enable
    end
    after { Retryable.disable }

    it "should throw an exception after the third fetch attempt" do
      allow(Kochiku::Worker).to receive(:logger) { double('logger', :warn => nil) }
      fetch_double = double('git fetch')
      expect(fetch_double).to receive(:run).exactly(3).times.and_raise(Cocaine::ExitStatusError)
      expect(Cocaine::CommandLine).to receive(:new).with('git fetch', anything).and_return(fetch_double).exactly(3).times

      expect { GitStrategy::LocalCache.send(:run_git_fetch) }.to raise_error(Cocaine::ExitStatusError)
    end
  end
end
