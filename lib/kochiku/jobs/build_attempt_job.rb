require 'rest-client'

class BuildAttemptJob < JobBase
  SQ_WEB_REPO_NAME = 'web-cache'
  SQ_WEB_TEST_COMMAND = "script/ci worker"
  SQ_WEB_REPO_URL = "git@git.squareup.com:square/web.git"

  # TODO: 3 stage deploy, deploy this update - deploy kochiku - then delete the else statement and 3 extra args
  def initialize(build_attempt_id, build_kind = nil, build_ref = nil, test_files = nil)
    if build_attempt_id.is_a?(Hash)
      settings_hash = build_attempt_id
      @build_attempt_id = settings_hash["build_attempt_id"]
      @build_ref = settings_hash["build_ref"]
      @build_kind = settings_hash["build_kind"]
      @test_files = settings_hash["test_files"]
      @repo_name = settings_hash["repo_name"]
      @test_command = settings_hash["test_command"]
      @repo_url = settings_hash["repo_url"]
      @options = settings_hash["options"]
    else
      @build_attempt_id = build_attempt_id
      @build_ref = build_ref
      @build_kind = build_kind
      @test_files = test_files
      @repo_name = SQ_WEB_REPO_NAME
      @test_command = SQ_WEB_TEST_COMMAND
      @repo_url = SQ_WEB_REPO_URL
    end
  end

  def perform
    Kochiku::Worker.logger.info("Build Attempt #{@build_attempt_id} perform starting")
    build_status = signal_build_is_starting
    return if build_status == :aborted

    Kochiku::Worker::GitRepo.inside_copy(@repo_name, @repo_url, @build_ref) do
      result = run_tests(@build_kind, @test_files, @test_command, @options) ? :passed : :failed
      signal_build_is_finished(result)
      collect_artifacts(Kochiku::Worker.build_strategy.artifacts_glob)
    end
    Kochiku::Worker.logger.info("Build Attempt #{@build_attempt_id} perform finished")
  end

  def collect_artifacts(artifacts_glob)
    benchmark("Build Attempt #{@build_attempt_id} collecting artifacts") do
      artifact_upload_url = "http://#{Kochiku::Worker.settings.build_master}/build_attempts/#{@build_attempt_id}/build_artifacts"

      Dir[*artifacts_glob].each do |path|
        if File.file?(path) && !File.zero?(path)
          Cocaine::CommandLine.new("gzip", path).run
          path += '.gz'

          payload = {:build_artifact => {:log_file => File.new(path)}}
          begin
            RestClient::Request.execute(:method => :post, :url => artifact_upload_url, :payload => payload, :headers => {:accept => :xml}, :timeout => 60 * 5)
          rescue RestClient::Exception => e
            Kochiku::Worker.logger.error("Upload of artifact (#{path}) failed: #{e.message}")
          end
        end
      end
    end
  end

  def on_exception(e)
    signal_build_is_finished(:errored)
    Kochiku::Worker.logger.error("Exception during build (#{@build_attempt_id}) failed:")
    Kochiku::Worker.logger.error(e)
    raise e
  end

  private

  def hostname
    `hostname`.strip
  end

  def run_tests(build_kind, test_files, test_command, options)
    Kochiku::Worker.logger.info("Running tests for #{@build_attempt_id}")
    Kochiku::Worker.build_strategy.execute_build(build_kind, test_files, test_command, options)
  end

  def signal_build_is_starting
    benchmark("Signal build attempt #{@build_attempt_id} starting") do
      build_start_url = "http://#{Kochiku::Worker.settings.build_master}/build_attempts/#{@build_attempt_id}/start"

      begin
        result = RestClient::Request.execute(:method => :post, :url => build_start_url, :payload => {:builder => hostname}, :headers => {:accept => :json})
        JSON.parse(result)["build_attempt"]["state"].to_sym
      rescue RestClient::Exception => e
        Kochiku::Worker.logger.error("Start of build (#{@build_attempt_id}) failed: #{e.message}")
        raise
      end
    end
  end

  def signal_build_is_finished(result)
    benchmark("Signal build attempt #{@build_attempt_id} finished") do
      build_finish_url = "http://#{Kochiku::Worker.settings.build_master}/build_attempts/#{@build_attempt_id}/finish"

      begin
        RestClient::Request.execute(:method => :post, :url => build_finish_url, :payload => {:state => result}, :headers => {:accept => :json}, :timeout => 60, :open_timeout => 60)
      rescue RestClient::Exception => e
        Kochiku::Worker.logger.error("Finish of build (#{@build_attempt_id}) failed: #{e.message}")
        raise
      end
    end
  end

  def benchmark(msg, &block)
    Kochiku::Worker.logger.info("[#{msg}] starting")
    start_time = Time.now
    begin
      yield
    ensure
      end_time = Time.now
      Kochiku::Worker.logger.info("[#{msg}] finished in #{end_time - start_time}")
    end
  end
end
