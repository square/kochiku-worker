$:.unshift(File.expand_path('../lib', File.dirname(__FILE__)))

require 'rubygems'
require 'bundler/setup'

require 'rspec'
require 'webmock/rspec'

require 'kochiku/worker'

Dir["#{File.dirname(__FILE__)}/support/**/*.rb"].each {|f| load f}


RSpec.configure do |config|
  config.mock_with :rspec

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  config.before :each do
    WebMock.disable_net_connect!

    # TODO: This is terrible. Need to either set up proper git fixtures, or
    # figure out the right seams such that a fake object can be supplied.
    allow(Cocaine::CommandLine).to receive(:new).
      with("git config --get remote.origin.url").
      and_return(double(:run => 'git@github.com:square/kochiku-worker.git'))
    allow(Cocaine::CommandLine).to receive(:new).with('git fetch', anything) { double('git fetch', :run => nil, :exit_status => 0) }
    allow(Cocaine::CommandLine).to receive(:new).with('git submodule update', anything) { double('git submodule update', :run => nil) }
    allow(Cocaine::CommandLine).to receive(:new).with('git rev-list', anything) { double('git rev-list', :run => nil, :exit_status => 0) }

    allow(Kochiku::Worker.logger).to receive(:info)
  end
end
