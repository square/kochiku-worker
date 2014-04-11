require "./config/deploy_hosts"

# The primary server in each group is considered to be the first unless any
# hosts have the primary property set.
role :worker, HostSettings.worker_hosts

# Set deploy_to to the path where you would like kochiku-worker to be deployed
# to on the server.
set :deploy_to, '/var/apps/kochiku-worker'
