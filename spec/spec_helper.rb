$:.unshift(File.expand_path('../lib', File.dirname(__FILE__)))

require 'rubygems'
require 'bundler/setup'

require 'rspec'
require 'webmock/rspec'
require 'cocaine'
require 'json'

require "kochiku/build_strategies/test_build_strategy"

require 'kochiku/worker'

Dir["#{File.dirname(__FILE__)}/support/**/*.rb"].each {|f| load f}


RSpec.configure do |config|
  config.mock_with :rspec

  config.before :each do
    WebMock.disable_net_connect!
    # Resque.stub(:enqueue)
    # JobBase.stub(:enqueue_in)

    Cocaine::CommandLine.stub(:new).with('git fetch', anything) { double('git fetch', :run => nil) }
    Cocaine::CommandLine.stub(:new).with('git submodule update', anything) { double('git submodule update', :run => nil) }
  end
end
