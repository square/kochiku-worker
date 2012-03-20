require 'resque/tasks'

namespace :resque do
  task :setup => [:'kochiku:worker:resque_setup']
end
