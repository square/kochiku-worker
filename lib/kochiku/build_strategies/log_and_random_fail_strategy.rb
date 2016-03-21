module BuildStrategy
  class LogAndRandomFailStrategy
    def execute_build(build_attempt_id, build_kind, test_files, test_command, timeout, options)
      system %[ruby -e "now = Time.now.usec; File.open('now.log', 'w') {|f|f.write(now)}; exit(now % 3 == 0 ? 1 : 0)"]
    end

    def log_files_glob
      ["now.log"]
    end
  end
end