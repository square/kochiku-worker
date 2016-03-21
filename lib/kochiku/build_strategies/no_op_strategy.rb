module BuildStrategy
  class NoOpStrategy
    def execute_build(build_attempt_id, build_kind, test_files, test_command, timeout, options)
      true
    end

    def log_files_glob
      []
    end
  end
end
