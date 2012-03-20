require "ostruct"
require "yaml"

module Kochiku
  module Worker
    class Settings < OpenStruct
      def initialize(root_dir)
        config_file = File.join(root_dir, "config/kochiku-worker.yml")
        user_defined_options = (File.exist?(config_file) && yaml = YAML.load_file(config_file)) ? yaml : {}

        contents = {}
        contents["build_master"] = user_defined_options["build_master"] || "localhost"
        contents["build_strategy"] = user_defined_options["build_strategy"] || "no_op"
        contents["redis_host"] = user_defined_options["redis_host"] || "localhost"

        @keys = contents.keys.sort

        super(contents)
      end

      def inspect
        self.class.name + ":\n" + @keys.map{|k|"  #{k.ljust(20)} = #{send(k.to_sym)}"}.join("\n") + "\n"
      end
    end
  end
end
