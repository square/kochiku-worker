require 'cocaine'

# report system status to kochiku master

class SystemStatusReportJob < JobBase
  class NfsCacheNotFoundError < StandardError; end

  NFS_MOUNT_LOCATION = '/mnt/nfs'.freeze
  REDIS_QUEUE = 'kochiku.data.collector:worker_system'.freeze

  class << self
    def perform
      Kochiku::Worker.redis_client.set(REDIS_QUEUE, nfs_cache_usage)
    end

    def nfs_cache_usage
      {
        shared_cache: disk_usage("#{NFS_MOUNT_LOCATION}/shared-cache/"),
        nfs_git: disk_usage("#{NFS_MOUNT_LOCATION}/git/")
      }.to_json
    end

    def disk_usage(disk)
      usage = Cocaine::CommandLine.new("df #{disk} | awk '{print $5}' | tail -1").run.chomp.gsub('%', '')
      raise NfsCacheNotFoundError, "Not mounted to /mnt/nfs" if usage.empty?

      usage
    end
  end
end
