module BuildStrategy
  def self.execute_with_timeout(command, timeout, log_file)
    dir = File.dirname(log_file)
    File.mkdir_p(dir) unless Dir.exists?(dir)
    File.open(log_file, "a") do |file|
      file.write(command + "\n")
    end
    pid = nil
    Bundler.with_clean_env do
      pid = Process.spawn(command, :out => [log_file, "a"], :err => [:child, :out])
    end

    Timeout.timeout(timeout) do
      Process.wait(pid)
    end
    $?.exitstatus == 0
  end

  class BuildAllStrategy
    class ErrorFoundInLogError < StandardError; end

    LOG_FILE = "log/stdout.log"

    def execute_build(build_kind, test_files, test_command, timeout, options)
      execute_with_timeout_and_kill(ci_command(build_kind, test_files, test_command, options), timeout)
    end

    def log_files_glob
      ['log/*log']
    end

    def execute_with_timeout_and_kill(command, timeout)
      begin
        BuildStrategy.execute_with_timeout(command, timeout, LOG_FILE)
      ensure
        kill_all_child_processes
        check_log_for_errors!
      end
    end

    def kill_all_child_processes
      did_kill = false
      (child_processes | processes_in_same_group).each do |process_to_kill|
        kill_process(process_to_kill)
        did_kill ||= true
      end

      if did_kill
        File.open(LOG_FILE, 'a') do |file|
          file.write("\n\n******** Process taking too long, Kochiku killing it NOW ************\n")
        end
      end
    end

    def kill_process(pid, sig = "HUP")
      begin
        Timeout.timeout(10) do
          Process.kill(sig, pid)
          Process.wait(pid)
        end
      rescue Timeout::Error
        # The process did not exit from SIGHUP within the timeout
        # no more CPU time for the child process
        kill_process(pid, 9) if sig == "HUP"
      rescue Errno::ESRCH, Errno::ECHILD # Process has already exited
      end
    end

    def child_processes
      descendants = Hash.new{|ht,k| ht[k] = [k] }
      Hash[*`ps -eo pid,ppid`.scan(/\d+/).map(&:to_i)].each do |pid, ppid|
        descendants[ppid] << descendants[pid]
      end
      ps_pid = $?.pid
      descendants[Process.pid].flatten - [Process.pid, ps_pid]
    end

    def processes_in_same_group
      `ps -eo pid,pgid`.split("\n").slice(1..-1).map  {|s| s.strip.split(/\s+/).map(&:to_i) }.map do |process_info|
        process_info.first if process_info.last == Process.getpgrp
      end.compact - [Process.pid, Process.ppid, Process.getpgrp, $?.pid]
    end

    private

    def ci_command(build_kind, test_files, test_command, options)
      ruby_command = if options && options["ruby"]
        "rvm --install --create use #{options["ruby"]}"
      else
        "if [ -e .rvmrc ]; then source .rvmrc; elif [ -e .ruby-version ]; then rvm --install --create use $(cat .ruby-version); fi"
      end
      (
        "env -i HOME=$HOME" +
        " PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:/usr/X11/bin:/usr/local/share/python:$M2" +
        " DISPLAY=localhost:1.0" +
        " TEST_RUNNER=#{build_kind}" +
        " RUBY=#{options["ruby"]}" +
        " MAVEN_OPTS='-Xms1024m -Xmx4096m -XX:PermSize=1024m -XX:MaxPermSize=2048m'" +
        " RUN_LIST=$TARGETS" +
        " bash --noprofile --norc -c 'source ~/.rvm/scripts/rvm ; #{ruby_command} ; ruby -v ; #{test_command}'"
      ).gsub("$TARGETS", test_files.join(','))
    end

    def check_log_for_errors!
      File.open(LOG_FILE, :encoding => 'UTF-8') do |file|
        file.each do |line|
          raise ErrorFoundInLogError.new(line) if known_error?(line)
        end
      end
    end

    @@known_errors = Regexp.union(
      [
        "couldn't find resque worker",
        "Resource temporarily unavailable",
        "Can't connect to local MySQL server through socket",
        "cucumber processes did not come up"
      ]
    )
    def known_error?(line)
      line =~ @@known_errors
    end
  end
end
