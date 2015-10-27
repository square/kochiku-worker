require "./config/staging_hosts"

# The primary server in each group is considered to be the first unless any
# hosts have the primary property set.
role :worker, HostSettings.worker_hosts

role :mac_worker, HostSettings.worker_hosts.select {|name| name.include? 'macbuild' }
role :ec2_worker, HostSettings.worker_hosts.select {|name| name.include? 'ec2' }

set :deploy_to, '/data/app/kochiku-worker'
set :repo_url, "git://git-mirror.corp.squareup.com/cii/kochiku-worker.git"
set :user, "square"
