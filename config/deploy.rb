require "rvm/capistrano"
set :rvm_type, :user
set :rvm_ruby_string, 'ruby-1.9.3-p327'

require 'bundler/capistrano' # adds bundle:install step to deploy pipeline

default_run_options[:env] = {'PATH' => '/usr/local/bin:$PATH'}

set :application, "Kochiku Worker"
set :repository,  "git@git.squareup.com:square/kochiku-worker.git"
set :branch, "master"
set :scm, :git
set :scm_command, 'git'

set :user, "square"
set :deploy_to, "~/kochiku-worker"
set :deploy_via, :remote_cache
set :keep_releases, 5
set :use_sudo, false

macbuilds = (1..22).map {|n| "macbuild%02d.sfo.squareup.com" % n }
role :mac_worker, *macbuilds
role :ec2_worker, *YAML.load(File.read('config/ec2-workers.yml')).each_slice(70).to_a[0]

after "deploy:setup", "kochiku:setup"
after "deploy:create_symlink", "kochiku:symlinks"
after "deploy:create_symlink", "kochiku:create_kochiku_worker_yaml"

namespace :deploy do
  desc "Restart the web application server and all of the build workers"
  task :restart do
    restart_mac_workers
    restart_ec2_workers
  end

  desc "Restart the EC2 workers"
  task :restart_ec2_workers, :roles => :ec2_worker do
    run <<-CMD
      running_kochiku_flavors=$(sudo monit summary | grep running | egrep -o 'kochiku-worker-(ci|web-cucumber|web-spec|spec-ci)');
      for flavor in $running_kochiku_flavors; do
        sudo monit restart $flavor;
      done;
    CMD
  end

  desc "Restart the macbuild workers"
  task :restart_mac_workers, :roles => :mac_worker do
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
  task :setup, :roles => [:mac_worker, :ec2_worker] do
    run "gem install bundler -v '~> 1.1.0' --conservative"
    run "mkdir -p #{shared_path}/build-partition"
    run "[ -d #{shared_path}/build-partition/web-cache ] || #{scm_command} clone --recursive git@git.squareup.com:square/web.git #{shared_path}/build-partition/web-cache"
  end

  task :symlinks, :roles => [:mac_worker, :ec2_worker] do
    run "ln -nfFs #{shared_path}/build-partition #{current_path}/tmp/build-partition"
  end

  task :create_kochiku_worker_yaml, :roles => [:mac_worker, :ec2_worker] do
    config =
      [ 'build_master: macbuild-master.sfo.squareup.com',
        'build_strategy: build_all',
        'redis_host: macbuild-master.sfo.squareup.com' ]

    run "echo '#{config.join("$")}' | tr '$' '\n' > #{current_path}/config/kochiku-worker.yml"
  end

  task :cleanup_zombies, :roles => [:mac_worker, :ec2_worker] do
    run "ps -eo 'pid ppid comm' |grep -i resque |grep Paused | awk '$2 == 1 { print $1 }' | xargs kill"
  end
end
