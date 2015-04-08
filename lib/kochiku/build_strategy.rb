module BuildStrategy

  def self.execute_with_timeout(command, timeout, log_file)
    exit_status = nil

    dir = File.dirname(log_file)
    FileUtils.mkdir_p(dir) unless Dir.exists?(dir)
    File.open(log_file, "a") do |file|
      file.write(Array(command).join(" ") + "\n")
    end
    pid = nil
    Bundler.with_clean_env do
      pid = Process.spawn(*command, :out => [log_file, "a"], :err => [:child, :out], :pgroup => true)
    end

    begin
      Timeout.timeout(timeout) do
        Process.wait(pid)
      end

      exit_status = ($?.exitstatus == 0)
    rescue Timeout::Error
      # Keeps this error out of Resque failures
      exit_status = false
    end

    return exit_status, pid
  end

  # run before forcibly killing a process or child-process
  # can be used to get a stack trace, etc.
  def self.on_terminate_hook(pid, command)
  end
end
