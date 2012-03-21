require 'bundler/setup'
$:.unshift(File.expand_path(File.join(File.dirname(__FILE__), 'lib')))

require 'resque/tasks'

Dir.glob('tasks/*.rake').each { |r| import r }
