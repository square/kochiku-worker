require 'bundler/setup'
Bundler.require

require 'logger'

require 'resque'

require 'kochiku/settings'
require 'kochiku/git_repo'
require 'kochiku/git_strategies/local_cache_strategy'
require 'kochiku/git_strategies/nfs_strategy'


require 'kochiku/build_strategies/build_all_strategy'
require 'kochiku/build_strategies/log_and_random_fail_strategy'
require 'kochiku/build_strategies/no_op_strategy'
require 'kochiku/build_strategy_factory'

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

      def build_strategy
        @build_strategy ||= BuildStrategyFactory.get_strategy(settings.build_strategy)
      end
    end
  end
end

Resque.redis = Redis.new(:host => Kochiku::Worker.settings.redis_host)
Resque.redis.namespace = "resque:kochiku"

Cocaine::CommandLine.logger = Kochiku::Worker.logger
