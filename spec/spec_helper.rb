$:.unshift(File.expand_path('../lib', File.dirname(__FILE__)))

require 'rubygems'
require 'bundler/setup'

require 'rspec'
require 'webmock/rspec'
require 'memfs'

require 'kochiku/worker'

Dir["#{File.dirname(__FILE__)}/support/**/*.rb"].each {|f| load f}

FileUtils.mkdir_p("log")
test_logger = Logger.new("log/test.log", 2)
test_logger.level = Logger::DEBUG
Kochiku::Worker.logger = test_logger

RSpec.configure do |config|
  config.expose_dsl_globally = false

  config.mock_with :rspec do |mocks|
    mocks.syntax = :expect
    mocks.patch_marshal_to_support_partial_doubles = false
  end

  config.mock_with :rspec do |expectations|
    expectations.syntax = :expect
  end

  config.disable_monkey_patching! # same as what's above

  config.before :suite do
    # Disable Retryable; enable for individual tests if desired.
    Retryable.disable
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
    allow(Cocaine::CommandLine).to receive(:new).with('git rev-list', anything) { double('git rev-list', :run => nil) }
  end
end
