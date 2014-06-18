# This is run on a Kochiku worker when the auto scaling algorithm wants to
# shrink the number of workers.
#
# It is likely that if you want to use auto scaling you will need to adjust the
# commands run by this job for your setup.
class ShutdownInstanceJob < JobBase
  def self.perform
    # Tell the parent Resque process to pause after it finishes processing this
    # job. It will be exited by monit.
    Process.kill("USR2", Process.ppid)

    # Shutdown the instance 1 minute from now. Requires NOPASSWD sudo
    pid = Process.spawn("sudo monit stop kochiku-worker; sudo shutdown -h +1m")
    Process.detach(pid)
  end
end
