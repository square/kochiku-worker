module BuildStrategy
  class BuildAllStrategy
    class ErrorFoundInLogError < StandardError; end

    LOG_FILE = "log/stdout.log"

    def execute_build(build_kind, test_files, test_command, timeout, options)
      execute_with_timeout_and_kill(ci_command(build_kind, test_files, test_command, options), timeout)
    end

    def log_files_glob
      ['log/*log','surefire-reports/*.html']
    end

    def execute_with_timeout_and_kill(command, timeout)
      BuildStrategy.execute_with_timeout(command, timeout, LOG_FILE)
    ensure
      kill_all_child_processes
      check_log_for_errors!
    end

    def kill_all_child_processes
      did_kill = false
      # killing processes_in_same_group breaks when kochiku-worker is being run by runit
      # because it tries to kill runit and all processes in runit that are being run as
      # the square user
      # remove processes_in_same_group for now
      #(child_processes | processes_in_same_group).each do |process_to_kill|
      child_processes.each do |process_to_kill|
        kill_process(process_to_kill)
        did_kill ||= true
      end

      if did_kill
        File.open(LOG_FILE, 'a') do |file|
          file.write("\n\n******** Process taking too long, Kochiku killing it NOW ************\n")
        end
      end
    end

    def kill_process(pid, sig = "TERM")
      begin
        Timeout.timeout(10) do
          Process.kill(sig, pid)
          Process.wait(pid)
        end
      rescue Timeout::Error
        # The process did not exit within the timeout
        # no more CPU time for the child process
        kill_process(pid, 9)
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
      ruby_command = if options["ruby"]
        "rvm --install --create use #{options["ruby"]}"
      else
        "if [ -e .rvmrc ]; then source .rvmrc; elif [ -e .ruby-version ]; then rvm --install --create use $(cat .ruby-version); fi"
      end
      (
        "env -i HOME=$HOME" +
        " USER=$USER" +
        " PATH=/usr/local/bin:/usr/bin:/bin:/usr/local/sbin:/usr/sbin:/sbin:/usr/X11/bin:$M2" +
        " DISPLAY=localhost:1.0" +
        " TEST_RUNNER=#{build_kind}" +
        " GIT_COMMIT=#{options["git_commit"]}" +
        " GIT_BRANCH=#{options["git_branch"]}" +
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
        "cucumber processes did not come up",
        "Mysql timed out, bailing",
        "Gem::RemoteFetcher::FetchError"
      ]
    )
    def known_error?(line)
      line =~ @@known_errors
    end
  end
end
