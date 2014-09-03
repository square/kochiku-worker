module BuildStrategy
  class BuildAllStrategy
    class ErrorFoundInLogError < StandardError; end

    LOG_FILE = "log/stdout.log"

    def execute_build(build_kind, test_files, test_command, timeout, options)
      if options['log_file_globs']
        @log_files = options['log_file_globs'] << LOG_FILE
      end
      execute_with_timeout_and_kill(ci_command(build_kind, test_files, test_command, options), timeout)
    end

    def log_files_glob
      @log_files ||= [LOG_FILE]
    end

    def execute_with_timeout_and_kill(command, timeout)
      success, pid = BuildStrategy.execute_with_timeout(command, timeout, LOG_FILE)
      success
    ensure
      did_kill = kill_process_group(pid, 15)

      if did_kill
        File.open(LOG_FILE, 'a') do |file|
          file.write("\n\n******** Process taking too long, Kochiku killing it NOW ************\n")
        end
      end

      check_log_for_errors! unless success
    end

    def kill_process_group(pid, sig = 15)
      process_timeout = false

      # Kill the head process
      # We cannot kill the process group if head is a zombie process
      begin
        Timeout.timeout(10) do
          Process.kill(sig, pid)
          Process.wait(pid)
        end
      rescue Timeout::Error
        process_timeout = true
        Process.kill(9, pid)
        Process.wait(pid)
      rescue Errno::ESRCH, Errno::ECHILD # Process has already exited
      end

      # Kill the rest of the process group
      begin
        Timeout.timeout(10) do
          if count_processes_in_same_group(pid) == 0
            return process_timeout
          else
            process_timeout = true
          end

          # (-sig) sends sig to the entire process group
          Process.kill(-sig, pid)

          # wait for all processes in group to exit
          while count_processes_in_same_group(pid) > 0 do
            sleep 1
          end
        end
      rescue Timeout::Error
        # The processes did not exit within the timeout
        # no more CPU time for the child processes
        sleep 1
        kill_process_group(pid, 9)
      rescue Errno::ESRCH, Errno::ECHILD # Process has already exited
      end
      process_timeout
    end

    def child_processes
      descendants = Hash.new{|ht,k| ht[k] = [k] }
      Hash[*`ps -eo pid,ppid`.scan(/\d+/).map(&:to_i)].each do |pid, ppid|
        descendants[ppid] << descendants[pid]
      end
      ps_pid = $?.pid
      descendants[Process.pid].flatten - [Process.pid, ps_pid]
    end

    def count_processes_in_same_group(pgid)
      open_processes = `ps -eo pgid | grep #{pgid}`
      open_processes.strip.split(/\s+/).length
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
