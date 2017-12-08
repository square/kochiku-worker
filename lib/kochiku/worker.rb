require 'bundler/setup'
Bundler.require

require 'logger'

require 'resque'

require 'kochiku/settings'
require 'kochiku/git_repo'
require 'kochiku/git_strategies/local_cache_strategy'
require 'kochiku/git_strategies/shared_cache_strategy'


require 'kochiku/build_strategy'
require 'kochiku/build_strategies/build_all_strategy'
require 'kochiku/build_strategies/log_and_random_fail_strategy'
require 'kochiku/build_strategies/no_op_strategy'
require 'kochiku/build_strategy_factory'

require 'kochiku/jobs/job_base'
require 'kochiku/jobs/build_attempt_job'
require 'kochiku/jobs/sanity_check_job'
require 'kochiku/jobs/shutdown_instance_job'
require 'kochiku/jobs/system_status_report_job'

module Kochiku
  module Worker
    class << self
      def settings
        @settings ||= Settings.new(File.expand_path(File.join(File.dirname(__FILE__), '..', '..')))
      end

      def logger
        @logger ||= begin
          default_logger = Logger.new(STDOUT)
          default_logger.formatter = proc do |severity, datetime, progname, msg|
            "%5s [%s] %d: %s\n" % [severity, datetime.strftime('%H:%M:%S %Y-%m-%d'), $$, msg2str(msg)]
          end
          Cocaine::CommandLine.logger = default_logger
          default_logger
        end
      end

      def logger=(logger)
        @logger = logger
        Cocaine::CommandLine.logger = @logger
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

      def redis_client
        Redis.new(host: Kochiku::Worker.settings.redis_host, port: Kochiku::Worker.settings.redis_port)
      end
    end
  end
end

Resque.redis = Kochiku::Worker.redis_client
Resque.redis.namespace = "resque:kochiku"

RestClient.log = Kochiku::Worker.logger
