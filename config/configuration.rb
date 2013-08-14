# set this to the location of your Kochiku build master
BUILD_MASTER_HOSTNAME = "kochiku.example.com"

# Change this if you want to run Redis on a different machine than the build master
# This needs to be the same as the Redis instance that the Kochiku application uses
REDIS_HOSTNAME = BUILD_MASTER_HOSTNAME

# Change this to the hostnames for the kochiku worker boxes that you want to deploy to
WORKER_HOSTNAMES = [
 "worker1.example.com",
 "worker2.example.com"
]