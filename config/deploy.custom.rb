require "rvm/capistrano"
set :rvm_type, :user
set :rvm_ruby_string, 'ruby-2.0.0-p353'

set :repository,  "git@git.squareup.com:square/kochiku-worker.git"
set :user, "square"

role :mac_worker, *HostSettings.worker_hosts.select {|name| name.include? 'macbuild' }
role :ec2_worker, *HostSettings.worker_hosts.select {|name| name.include? 'ec2' }

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
