
require 'kochiku/settings'
require 'kochiku/git_repo'

require 'kochiku/jobs/job_base'
require 'kochiku/jobs/build_attempt_job'

module Kochiku
  module Worker
    class << self
      def settings
        @settings ||= Settings.new(File.expand_path(File.join(File.dirname(__FILE__), '..', '..')))
      end

      def logger
        return @logger if @logger

        log_dir = File.expand_path(File.join(File.dirname(__FILE__), '..', '..', 'log'))
        log_file = File.open(File.join(log_dir, 'worker.log'), File::WRONLY | File::APPEND)
        @logger = Logger.new(log_file)
      end
    end
  end
end