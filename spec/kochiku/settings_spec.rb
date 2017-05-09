require 'spec_helper'

RSpec.describe Kochiku::Worker::Settings do
  describe "#initialize" do
    around do |example|
      MemFs.activate do
        example.run
      end
    end

    let(:settings) { Kochiku::Worker::Settings.new('.') }

    it 'sets default values when a config file is not present' do
      expect(settings.kochiku_web_server_host).to eq "localhost"
      expect(settings.kochiku_web_server_protocol).to be_nil
      expect(settings.build_strategy).to eq "no_op"
      expect(settings.redis_host).to eq "localhost"
      expect(settings.redis_port).to eq  "6379"
      expect(settings.git_strategy).to eq "localcache"
      expect(settings.git_shared_root).to be_nil
      expect(settings.logstreamer_port).to be_nil
    end

    it 'sets default values when the config file is empty' do
      write_config_file('---')
      expect(settings.kochiku_web_server_host).to eq "localhost"
    end

    it 'loads a YAML file with settings' do
      write_config_file(<<-YAML)
        kochiku_web_server_protocol: https
        redis_port: 1234
      YAML

      expect(settings.kochiku_web_server_protocol).to eq "https"
      expect(settings.redis_host).to eq "localhost"
      expect(settings.redis_port).to eq 1234
    end

    it 'loads a YAML file with settings' do
      write_config_file(<<-YAML)
        kochiku_web_server_protocol: https
        redis_port: 1234
      YAML

      expect(settings.kochiku_web_server_protocol).to eq 'https'
      expect(settings.redis_port).to eq 1234
    end

    it 'allows interpreting ERB in the config file' do
      write_config_file(<<-YAML)
        redis_port: <%= 123 * 10 %>
      YAML

      expect(settings.redis_port).to eq 1230
    end

    it 'raises when there is no git_shared_root for the shared cache strategy' do
      write_config_file(<<-YAML)
        git_strategy: sharedcache
        git_shared_root:
      YAML

      expect { settings }.to raise_error(
        StandardError,
        'git_shared_root required for sharedcache.'
      )
    end

    it 'raises when there is an invalid logstreamer port' do
      write_config_file(<<-YAML)
        logstreamer_port: foo
      YAML

      expect { settings }.to raise_error(
        StandardError,
        'logstreamer_port must be valid port number.'
      )
    end

    def write_config_file(contents)
      MemFs.touch('config/kochiku-worker.yml')
      File.open('config/kochiku-worker.yml', 'w') { |f| f.write(contents) }
    end
  end
end
