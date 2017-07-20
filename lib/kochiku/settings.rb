require "ostruct"
require "yaml"

module Kochiku
  module Worker
    class Settings < OpenStruct
      def initialize(root_dir)
        config_file = File.join(root_dir, "config/kochiku-worker.yml")
        user_defined_options = load_config(config_file) || {}

        contents = {}
        contents["kochiku_web_server_host"] = user_defined_options["kochiku_web_server_host"] || "localhost"
        contents["kochiku_web_server_protocol"] = user_defined_options["kochiku_web_server_protocol"]
        contents["build_strategy"] = user_defined_options["build_strategy"] || "no_op"
        contents["redis_host"] = user_defined_options["redis_host"] || "localhost"
        contents["redis_port"] = user_defined_options["redis_port"] || "6379"
        contents["git_strategy"] = user_defined_options["git_strategy"] || "localcache"
        contents["git_shared_root"] = user_defined_options["git_shared_root"]
        contents["aws_access_key"] = user_defined_options["aws_access_key"]
        contents["aws_secret_key"] = user_defined_options["aws_secret_key"]
        contents["logstreamer_port"] = user_defined_options['logstreamer_port']

        validate!(contents)

        @keys = contents.keys.sort

        super(contents)
      end

      def validate!(config)
        raise 'git_shared_root required for sharedcache.' if config["git_strategy"] == "sharedcache" && config["git_shared_root"].nil?
        raise 'logstreamer_port must be valid port number.' if config['logstreamer_port'] && !(config['logstreamer_port'].is_a?(Integer))
      end

      def inspect
        self.class.name + ":\n" + @keys.map{|k|"  #{k.ljust(20)} = #{send(k.to_sym)}"}.join("\n") + "\n"
      end

      private

      def load_config(config_file)
        if File.exist?(config_file)
          config_yaml = ERB.new(File.read(config_file)).result
          YAML.load(config_yaml)
        end
      end
    end
  end
end
