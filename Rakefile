require 'bundler/setup'
$:.unshift(File.expand_path(File.join(File.dirname(__FILE__), 'lib')))

require 'resque/tasks'

Dir.glob('tasks/*.rake').each { |r| import r }

# require 'rspec/core/rake_task'
# desc "run spec tests"
# RSpec::Core::RakeTask.new(:spec) do |t|
#   t.pattern = 'spec/**/*_spec.rb'
# end
