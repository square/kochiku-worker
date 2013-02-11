require 'rest-client'

class BuildAttemptJob < JobBase
  def initialize(build_options)
    @build_attempt_id = build_options["build_attempt_id"]
    @build_ref = build_options["build_ref"]
    @build_kind = build_options["build_kind"]
    @test_files = build_options["test_files"]
    @repo_name = build_options["repo_name"]
    @test_command = build_options["test_command"]
    @repo_url = build_options["repo_url"]
    @timeout = build_options["timeout"]
    @options = build_options["options"]
  end

  def logger
    Kochiku::Worker.logger
  end

  def perform
    logger.info("Build Attempt #{@build_attempt_id} perform starting")
    build_status = signal_build_is_starting
    return if build_status == :aborted

    Kochiku::Worker::GitRepo.inside_copy(@repo_name, @repo_url, @build_ref) do
      result = run_tests(@build_kind, @test_files, @test_command, @timeout, @options) ? :passed : :failed
      signal_build_is_finished(result)
      collect_artifacts(Kochiku::Worker.build_strategy.artifacts_glob)
    end
    logger.info("Build Attempt #{@build_attempt_id} perform finished")
  end

  def collect_artifacts(artifacts_glob)
    benchmark("Build Attempt #{@build_attempt_id} collecting artifacts") do
      Dir[*artifacts_glob].each do |path|
        if File.file?(path) && !File.zero?(path)
          Cocaine::CommandLine.new("gzip", path).run
          path += '.gz'
          upload_artifact_file(File.new(path))
        end
      end
    end
  end

  def on_exception(e)
    logger.error("Exception during build (#{@build_attempt_id}) failed:")
    logger.error(e)

    signal_build_is_finished(:errored)
    collect_artifacts(Kochiku::Worker.build_strategy.artifacts_glob)
    message = StringIO.new
    message.puts(e.message)
    message.puts(e.backtrace)
    # Need to override path method for RestClient to upload this correctly
    def message.path
      'error.txt'
    end
    upload_artifact_file(message)

    super
  end

  private

  def hostname
    `hostname`.strip
  end

  def run_tests(build_kind, test_files, test_command, timeout, options)
    logger.info("Running tests for #{@build_attempt_id}")
    Kochiku::Worker.build_strategy.execute_build(build_kind, test_files, test_command, timeout, options)
  end

  def signal_build_is_starting
    benchmark("Signal build attempt #{@build_attempt_id} starting") do
      build_start_url = "http://#{Kochiku::Worker.settings.build_master}/build_attempts/#{@build_attempt_id}/start"

      begin
        result = RestClient::Request.execute(:method => :post, :url => build_start_url, :payload => {:builder => hostname}, :headers => {:accept => :json})
        JSON.parse(result)["build_attempt"]["state"].to_sym
      rescue RestClient::Exception => e
        logger.error("Start of build (#{@build_attempt_id}) failed: #{e.message}")
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
        logger.error("Finish of build (#{@build_attempt_id}) failed: #{e.message}")
        raise
      end
    end
  end

  def upload_artifact_file(file)
    artifact_upload_url = "http://#{Kochiku::Worker.settings.build_master}/build_attempts/#{@build_attempt_id}/build_artifacts"

    payload = {:build_artifact => {:log_file => file}}
    begin
      RestClient::Request.execute(:method => :post, :url => artifact_upload_url, :payload => payload, :headers => {:accept => :xml}, :timeout => 60 * 5)
    rescue RestClient::Exception => e
      logger.error("Upload of artifact (#{file.to_s}) failed: #{e.message}")
    end
  end

  def benchmark(msg, &block)
    logger.info("[#{msg}] starting")
    start_time = Time.now
    begin
      yield
    ensure
      end_time = Time.now
      logger.info("[#{msg}] finished in #{end_time - start_time}")
    end
  end
end
