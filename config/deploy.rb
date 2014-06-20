# Lock version to protect against cap command being called without bundle exec
# and executing with another version
lock '3.2.1'

set :application, "kochiku-worker"
set :repo_url,  "https://github.com/square/kochiku-worker.git"
set :user, "kochiku"

ask :branch, proc { `git rev-parse --abbrev-ref HEAD`.chomp }

# Default value for :format is :pretty
# set :format, :pretty

# Default value for :log_level is :debug
# set :log_level, :debug

# Default value for :pty is false
# set :pty, true

set :linked_dirs, %w{log}

# Default value for default_env is {}
# set :default_env, { path: "/opt/ruby/bin:$PATH" }

# Reference Capistrano's flow diagram for help choosing hooks
# http://capistranorb.com/documentation/getting-started/flow/
before "deploy:started", "kochiku:setup"
after  "deploy:symlink:shared", "kochiku:symlinks"
before "deploy:updated", "kochiku:create_kochiku_worker_yaml"

# warn if a legacy deploy deploy.custom.rb is in place
if File.exist?(File.expand_path('deploy.custom.rb', File.dirname(__FILE__)))
  warn "Kochiku-worker has upgraded to Capistrano 3. Placing custom capistrano config in deploy.custom.rb is no longer supported. Please move Capistrano settings to config/deploy/production.rb and remove deploy.custom.rb to make this message go away."
  exit(1)
end
