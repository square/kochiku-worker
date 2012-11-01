module BuildStrategy
  class NoOpStrategy
    def execute_build(build_kind, test_files, test_command, timeout, options)
      true
    end

    def artifacts_glob
      []
    end
  end
end
