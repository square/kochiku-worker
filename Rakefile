require 'rspec'
require 'rspec/core/rake_task'

require 'resque/tasks'

Dir.glob('tasks/*.rake').each { |r| import r }

task :default => :spec

desc "Run all specs in spec directory"
RSpec::Core::RakeTask.new(:spec) do |t|
  t.pattern = "./spec/**/*_spec.rb"
end
