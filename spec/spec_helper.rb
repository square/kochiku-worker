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

    Cocaine::CommandLine.stub(:new).with('git fetch', anything) { double('git fetch', :run => nil) }
    Cocaine::CommandLine.stub(:new).with('git submodule update', anything) { double('git submodule update', :run => nil) }

    Kochiku::Worker.logger.stub(:info)
  end
end
