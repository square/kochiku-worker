
require 'rubygems'
require 'bundler/setup'

require 'logger'

require 'resque'
Resque.redis.namespace = "resque:kochiku"

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
        @logger ||= Logger.new(STDOUT).tap do |logger|
          logger.formatter = proc do |severity, datetime, progname, msg|
            "%5s [%s] %d: %s: %s\n" % [severity, datetime.strftime('%H:%M:%S %Y-%m-%d'), $$, progname, msg2str(msg)]
          end
        end
      end

      def msg2str(msg)
        case msg
        when ::String
          msg
        when ::Exception
          "#{ msg.message } (#{ msg.class })\n" <<
            (msg.backtrace || []).join("\n")
        else
          msg.inspect
        end
      end

    end
  end
end
