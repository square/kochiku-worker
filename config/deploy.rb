require "rvm/capistrano"
require "configuration"
set :rvm_type, :user
set :rvm_ruby_string, 'ruby-2.0.0'

require 'bundler/capistrano' # adds bundle:install step to deploy pipeline

default_run_options[:env] = {'PATH' => '/usr/local/bin:$PATH'}

set :application, "Kochiku Worker"
set :repository,  "https://github.com/square/kochiku-worker.git"
set :branch, "master"
set :scm, :git
set :scm_command, 'git'

set :user, "kochiku"
set :deploy_to, "~/kochiku-worker"
set :deploy_via, :remote_cache
set :keep_releases, 5
set :use_sudo, false

role :worker, WORKER_HOSTNAMES

after "deploy:setup", "kochiku:setup"
after "deploy:create_symlink", "kochiku:symlinks"
after "deploy:create_symlink", "kochiku:create_kochiku_worker_yaml"

namespace :deploy do
  desc "Restart all of the build workers"
  # Assumes your workers are monitored by Monit
  task :restart, :roles => :workers do
    run 'sudo monit restart kochiku-worker'
  end
end

namespace :kochiku do
  task :setup, :roles => :workers  do
    run "gem install bundler -v '~> 1.1.0' --conservative"
    run "mkdir -p #{shared_path}/build-partition"
  end

  task :symlinks, :roles => :workers do
    run "ln -nfFs #{shared_path}/build-partition #{current_path}/tmp/build-partition"
  end

  task :create_kochiku_worker_yaml, :roles => :workers  do
    config =
      [ "build_master: #{BUILD_MASTER_HOSTNAME}",
        'build_strategy: build_all',
        "redis_host: #{REDIS_HOSTNAME}" ]

    run "echo '#{config.join("$")}' | tr '$' '\n' > #{current_path}/config/kochiku-worker.yml"
  end

  task :cleanup_zombies, :roles => :workers do
    run "ps -eo 'pid ppid comm' |grep -i resque |grep Paused | awk '$2 == 1 { print $1 }' | xargs kill"
  end
end
