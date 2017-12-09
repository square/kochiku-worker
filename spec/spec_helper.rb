$:.unshift(File.expand_path('../lib', File.dirname(__FILE__)))

# Setup env variable to use as a trigger for log level during testing
ENV['RACK_ENV'] = 'test'

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
  end
end
