require 'cocaine'

# Check a list of worker attributes to make sure worker is in functional state

class SanityCheckJob < JobBase
  class << self
    def perform
      host_services_recover_script = File.expand_path('../../../script/host_services_recover', File.dirname(__FILE__))
      Cocaine::CommandLine.new(host_services_recover_script).run if hostname_check.nil?
    end

    def hostname_check
      %x('hostname').chomp =~ /(sjc1b|sjc2b|iad2b)|(^worker-\d+-\d+-\d+-\d+\.ec2$)/
    end
  end
end
