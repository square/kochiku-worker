module BuildStrategy
  class BuildAllStrategy
    def execute_build(build_kind, test_files)
      execute_with_timeout "env -i HOME=$HOME"+
      " PATH=/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin:/usr/X11/bin"+
      " TEST_RUNNER=#{build_kind}"+
      " RUN_LIST=#{test_files.join(',')}"+
      " bash --noprofile --norc -c 'ruby -v ; source ~/.rvm/scripts/rvm ; source .rvmrc ; mkdir log ; script/ci worker 2>log/stderr.log 1>log/stdout.log'"
    end

    def artifacts_glob
      ['log/*log', 'spec/reports/*.xml', 'features/reports/*.xml']
    end

    def execute_with_timeout(command, timeout = 60 * 60)
      pid = Process.spawn(command)
      begin
        Timeout.timeout(timeout) do
          Process.wait(pid)
        end
        true
      rescue Timeout::Error
        # Kill the hung job and wait for the kill to complete
        Process.kill(9, pid)
        Process.wait
        false
      end
    end
  end
end
