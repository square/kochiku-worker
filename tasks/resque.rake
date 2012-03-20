require 'resque/tasks'

namespace :resque do
  task :setup do
    require 'kochiku/worker'
    require "kochiku/build_strategies/production_build_strategy"
  end
end
