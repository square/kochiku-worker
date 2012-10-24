module BuildStrategy
  class BuildAllStrategy
    LOG_FILE = "log/stdout.log"
    FORTY_MINUTES = 2400

    def execute_build(build_kind, test_files, test_command, options)
      execute_with_timeout(ci_command(build_kind, test_files, test_command, options), FORTY_MINUTES)
    end

    def artifacts_glob
      ['log/*log', 'spec/reports/*.xml', 'features/reports/*.xml']
    end

    def execute_with_timeout(command, timeout)
      Dir.mkdir("log") unless Dir.exists?("log")
      File.open(LOG_FILE, "a") do |file|
        file.write("******** Running command ********\n")
        file.write(command + "\n")
        file.write("*********************************\n")
      end
      pid = Process.spawn(command, :err => LOG_FILE, :out => LOG_FILE)
      begin
        Timeout.timeout(timeout) do
          Process.wait(pid)
        end
        $? == 0
      rescue Timeout::Error
        kill_all_child_processes
        false
      end
    end

    def kill_all_child_processes
      child_processes.each do |process_to_kill|
        begin
          # Kill the hung job and wait for the kill to complete
          Process.kill(9, process_to_kill)
          Process.wait(process_to_kill)
        rescue Errno::ESRCH, Errno::ECHILD # Process has already exited
        end
      end
    end

    def all_related_processes
      # The slice removes the PID line
      `ps -x -o "pid" -g #{Process.getpgrp}`.split("\n").slice(1..-1).map { |line| line.strip.split(/\s+/).first }.map(&:to_i)
    end

    def child_processes
      # Process.pid is this process, Process.getpgrp is resque, $? is the process that ran the ps
      kill_not_required = [Process.pid, Process.getpgrp, $?.pid]
      processes_to_kill = all_related_processes - kill_not_required
    end

    private
    def ci_command(build_kind, test_files, test_command, options)
      rvm_command = if options && options["rvm"]
        "rvm --install use #{options["rvm"]}"
      else
        "source .rvmrc"
      end
      ("env -i HOME=$HOME"+
      " PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:/usr/X11/bin:$M2"+
      " DISPLAY=localhost:1.0" +
      " TEST_RUNNER=#{build_kind}"+
      " MAVEN_OPTS='-Xms1024m -Xmx4096m -XX:PermSize=1024m -XX:MaxPermSize=2048m'"+
      " RUN_LIST=$TARGETS"+
      " bash --noprofile --norc -c 'ruby -v ; source ~/.rvm/scripts/rvm ; #{rvm_command} ; #{test_command}'").gsub("$TARGETS", test_files.join(','))
    end
  end
end
