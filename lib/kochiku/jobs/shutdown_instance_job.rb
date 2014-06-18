# This is run on a Kochiku worker when the auto scaling algorithm wants to
# shrink the number of workers.
#
# It is likely that if you want to use auto scaling you will need to adjust the
# commands run by this job for your setup.
class ShutdownInstanceJob < JobBase
  def self.perform
    # Tell the parent Resque process to exit after it finishes processing this job
    Process.kill("QUIT", Process.ppid)

    # Shutdown the instance 1 minute from now. Requires NOPASSWD sudo
    pid = Process.spawn("sudo shutdown -h +1m")
    Process.detach(pid)
  end
end
