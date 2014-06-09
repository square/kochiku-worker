# This is run on a Kochiku worker when we are trying to shrink the number of workers.
class ShutdownInstanceJob < JobBase
  def self.perform
    pid = Process.spawn("sudo monit stop kochiku-worker-spec-ci; sudo shutdown -h +1m")
    Process.detach(pid)
  end
end
