require 'rspec'
require 'rspec/core/rake_task'

Dir.glob('lib/kochiku/tasks/*.rake').each { |r| import r }

task :default => :spec

desc "Run all specs in spec directory"
RSpec::Core::RakeTask.new(:spec) do |t|
  t.pattern = "./spec/**/*_spec.rb"
end
