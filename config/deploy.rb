require "rvm/capistrano"
set :rvm_type, :user
set :rvm_ruby_string, 'ruby-1.9.3-p194@kochiku-worker'

require 'bundler/capistrano' # adds bundle:install step to deploy pipeline

default_run_options[:env] = {'PATH' => '/usr/local/bin:$PATH'}

set :application, "Kochiku Worker"
set :repository,  "git@git.squareup.com:square/kochiku-worker.git"
set :branch, "master"
set :scm, :git
set :scm_command, 'git'

set :user, "square"
set :deploy_to, "/Users/square/kochiku-worker"
set :deploy_via, :remote_cache
set :keep_releases, 5
set :use_sudo, false

macbuilds = (1..26).map {|n| "macbuild%02d.sfo.squareup.com" % n }
role :worker, *macbuilds

after "deploy:setup", "kochiku:setup"
after "deploy:create_symlink", "kochiku:symlinks"
after "deploy:create_symlink", "kochiku:create_kochiku_worker_yaml"

namespace :deploy do
  desc "Restart the web application server and all of the build workers"
  task :restart do
    restart_workers
  end

  desc "Restart the build workers"
  task :restart_workers, :roles => :worker do
    # the trailing semicolons are required because this is passed to the shell as a single string
    run <<-CMD
      resque1_pid=$(cat #{shared_path}/pids/resque1.pid);
      resque2_pid=$(cat #{shared_path}/pids/resque2.pid);
      kill -QUIT $resque1_pid;
      kill -QUIT $resque2_pid;

      while ps x | egrep -q "^($resque1_pid|$resque2_pid)"; do
        echo "Waiting for Resque workers to stop on $HOSTNAME...";
        sleep 5;
      done;
    CMD
  end
end

namespace :kochiku do
  task :setup, :roles => [:worker] do
    run "rvm gemset create 'kochiku-worker'"
    run "gem install bundler -v '~> 1.1.0' --conservative"
    run "mkdir -p #{shared_path}/build-partition"
    run "[ -d #{shared_path}/build-partition/web-cache ] || #{scm_command} clone --recursive git@git.squareup.com:square/web.git #{shared_path}/build-partition/web-cache"
  end

  task :symlinks, :roles => [:worker] do
    run "ln -nfFs #{shared_path}/build-partition #{current_path}/tmp/build-partition"
  end

  task :create_kochiku_worker_yaml, :roles => [:worker] do
    worker_config = <<-EOF
      build_master: macbuild-master.sfo.squareup.com
      build_strategy: build_all
      redis_host: macbuild-master.sfo.squareup.com
    EOF

    put worker_config, "#{current_path}/config/kochiku-worker.yml"
  end

  task :cleanup_zombies, :roles => [:worker] do
    run "ps -eo 'pid ppid comm' |grep -i resque |grep Paused | awk '$2 == 1 { print $1 }' | xargs kill"
  end
end
