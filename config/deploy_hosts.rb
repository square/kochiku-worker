class ConfigAccessor
  def initialize(yaml)
    @hash = YAML.load(yaml)
  end

  def kochiku_web_protocol
    @hash['kochiku_web_protocol']
  end

  def kochiku_web_host
    @hash['kochiku_web_host']
  end

  def redis_host
    @hash['redis_host']
  end

  def worker_hosts
    @hash['worker_hosts']
  end

  def logstreamer_port
    @hash['logstreamer_port']
  end
end

CONF_FILE = File.expand_path('deploy_hosts.yml', File.dirname(__FILE__))

if !File.exist?(CONF_FILE)
  raise "#{CONF_FILE} is required to deploy kochiku-worker"
else
  HostSettings = ConfigAccessor.new(File.read(CONF_FILE))
end
