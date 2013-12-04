$:.unshift(File.expand_path('../lib', File.dirname(__FILE__)))

require 'rubygems'
require 'bundler/setup'

require 'rspec'
require 'webmock/rspec'

require 'kochiku/worker'

Dir["#{File.dirname(__FILE__)}/support/**/*.rb"].each {|f| load f}


RSpec.configure do |config|
  config.mock_with :rspec

  config.before :each do
    WebMock.disable_net_connect!

    # TODO: This is terrible. Need to either set up proper git fixtures, or
    # figure out the right seams such that a fake object can be supplied.
    Cocaine::CommandLine.stub(:new).
      with("git config --get remote.origin.url").
      and_return(double(:run => 'git@github.com:square/kochiku-worker.git'))
    Cocaine::CommandLine.stub(:new).with('git fetch', anything) { double('git fetch', :run => nil, :exit_status => 0) }
    Cocaine::CommandLine.stub(:new).with('git submodule update', anything) { double('git submodule update', :run => nil) }
    Cocaine::CommandLine.stub(:new).with('git rev-list', anything) { double('git rev-list', :run => nil, :exit_status => 0) }

    Kochiku::Worker.logger.stub(:info)
  end
end
