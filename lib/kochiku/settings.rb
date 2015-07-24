require "ostruct"
require "yaml"

module Kochiku
  module Worker
    class Settings < OpenStruct
      def initialize(root_dir)
        config_file = File.join(root_dir, "config/kochiku-worker.yml")
        user_defined_options = (File.exist?(config_file) && yaml = YAML.load_file(config_file)) ? yaml : {}

        contents = {}
        contents["kochiku_web_server_host"] = user_defined_options["kochiku_web_server_host"] || "localhost"
        contents["kochiku_web_server_protocol"] = user_defined_options["kochiku_web_server_protocol"]
        contents["build_strategy"] = user_defined_options["build_strategy"] || "no_op"
        contents["redis_host"] = user_defined_options["redis_host"] || "localhost"
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
    end
  end
end
