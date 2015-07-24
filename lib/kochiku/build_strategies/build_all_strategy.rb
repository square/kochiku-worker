require 'fileutils'

module BuildStrategy
  class BuildAllStrategy
    class ErrorFoundInLogError < StandardError; end

    LOG_FILE = "log/stdout.log"
    STACK_TRACES = "log/stack_traces/*.log"
    KILL_TIMEOUT = 10

    def execute_build(build_attempt_id, build_kind, test_files, test_command, timeout, options)
      if options['log_file_globs']
        @log_files = options['log_file_globs'] + [LOG_FILE, STACK_TRACES]
      end
      @build_attempt_id = build_attempt_id
      hardlink_log(LOG_FILE)
      execute_with_timeout_and_kill(ci_command(build_kind, test_files, test_command, options), timeout)
    end

    # log persistence needed for logstreamer
    def hardlink_log(log)
      FileUtils.mkdir_p("log")
      FileUtils.touch(log)

      kochiku_base_dir = File.join(__dir__, "../../..")

      FileUtils.mkdir_p("#{kochiku_base_dir}/logstreamer/logs/#{@build_attempt_id}/")
      FileUtils.ln(log, "#{kochiku_base_dir}/logstreamer/logs/#{@build_attempt_id}/stdout.log")
    end

    def log_files_glob
      @log_files ||= [LOG_FILE, STACK_TRACES]
    end

    def execute_with_timeout_and_kill(command, timeout)
      success, pid = BuildStrategy.execute_with_timeout(command, timeout, LOG_FILE)
      success
    ensure
      processes_killed = kill_process_group(pid, 15)

      if processes_killed.length > 0
        File.open(LOG_FILE, 'a') do |file|
          file.write("\n\n******** The following process(es) taking too long, Kochiku killing NOW ************\n")
          file.write(processes_killed.join("\n"))
        end
      end

      check_log_for_errors! unless success
    end

    # returns array of the process commands killed (or empty array if none).
    def kill_process_group(pid, sig = 15)
      processes_killed = []

      # Kill the head process
      # We cannot kill the process group if head is a zombie process
      begin
        Timeout.timeout(KILL_TIMEOUT) do
          ps_entry = `ps p #{pid} -o pid,state,command | tail -n +2`.strip

          unless ps_entry == ""
            parsed_entry = /(?<pid>.*?)\s+(?<state>.*?)\s+(?<command>.*)/.match(ps_entry)
            ps_pid = parsed_entry["pid"].to_i
            ps_state = parsed_entry["state"]
            ps_command = parsed_entry["command"]

            # Don't record zombie processes
            unless ps_state =~ /Z/
              BuildStrategy.on_terminate_hook(ps_pid, ps_command)
              processes_killed << ps_command
            end
          end

          Process.kill(sig, pid)
          Process.wait(pid)
        end
      rescue Timeout::Error
        Process.kill(9, pid)
        Process.wait(pid)
      rescue Errno::ESRCH, Errno::ECHILD # Process has already exited
      end

      # Kill the rest of the process group
      begin
        Timeout.timeout(KILL_TIMEOUT) do
          list_processes = processes_in_same_group(pid)
          if list_processes.empty?
            return processes_killed
          else
            list_processes.each do |process_id, command|
              BuildStrategy.on_terminate_hook(process_id, command)
            end
            processes_killed += list_processes.values
          end

          # (-sig) sends sig to the entire process group
          Process.kill(-sig, pid)

          # wait for all processes in group to exit
          while processes_in_same_group(pid).length > 0 do
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

      processes_killed
    end

    # returns hash of pid => command for processes in group pgid
    def processes_in_same_group(pgid)
      open_processes = `ps -eo pid,pgid,state,command | tail -n +2`.strip.split("\n").map { |x| x.strip }
      parsed_processes = open_processes.map { |x| /(?<pid>.*?)\s+(?<pgid>.*?)\s+(?<state>.*?)\s+(?<command>.*)/.match(x) }
                                       .select { |x| x["pgid"].to_i == pgid && x["state"] !~ /Z/ }
      pid_commands = {}

      parsed_processes.each do |process|
        pid_commands[process["pid"].to_i] = process["command"]
      end

      return pid_commands
    end

    private

    def ci_command(build_kind, test_files, test_command, options)
      ruby_command = if options["ruby"]
        "rvm --install --create use #{options["ruby"]}"
      else
        "if [ -e .rvmrc ]; then source .rvmrc; elif [ -e .ruby-version ]; then rvm --install --create use $(cat .ruby-version); fi"
      end

      java_options = ""

      if build_kind == "maven" && options['total_workers'] && options['worker_chunk']
        java_options = " _JAVA_OPTIONS=\"-Dsquare.test.chunkCount=#{options['total_workers']} -Dsquare.test.runChunk=#{options['worker_chunk']}\""
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
        " KOCHIKU_ENV=#{options["kochiku_env"]}" +
        java_options +
        " bash --noprofile --norc -c 'if [ -f ~/.rvm/scripts/rvm ]; then source ~/.rvm/scripts/rvm; elif [ -f /usr/local/rvm/scripts/rvm ]; then source /usr/local/rvm/scripts/rvm; fi; #{ruby_command} ; ruby -v ; #{test_command}'"
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
