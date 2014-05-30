module BuildStrategy
  def self.execute_with_timeout(command, timeout, log_file)
    dir = File.dirname(log_file)
    FileUtils.mkdir_p(dir) unless Dir.exists?(dir)
    File.open(log_file, "a") do |file|
      file.write(Array(command).join(" ") + "\n")
    end
    pid = nil
    Bundler.with_clean_env do
      pid = Process.spawn(*command, :out => [log_file, "a"], :err => [:child, :out])
    end

    begin
      Timeout.timeout(timeout) do
        Process.wait(pid)
      end
      $?.exitstatus == 0
    rescue Timeout::Error
      # Keeps this error out of Resque failures
      return false
    end
  end
end
