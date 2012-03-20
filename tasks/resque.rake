require 'resque/tasks'

namespace :resque do
  task :setup do
    require 'kochiku/worker'
  end
end
