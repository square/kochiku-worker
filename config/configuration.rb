class SettingsAccessor
  def initialize(yaml)
    @hash = YAML.load(yaml).with_indifferent_access
  end

  def kochiku_web_host
    @hash[:kochiku_web_host]
  end

  def redis_host
    @hash[:redis_host]
  end

  def worker_hosts
    @hash[:worker_hosts]
  end
end

# Load application settings for Kochiku worker
CONF_FILE = File.expand_path('application.yml', __FILE__)

if !File.exist?(CONF_FILE)
  raise "#{CONF_FILE} is required to deploy kochiku-worker"
else
  Settings = SettingsAccessor.new(File.read(CONF_FILE))
end
