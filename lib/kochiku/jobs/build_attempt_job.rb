require 'rest-client'

class BuildAttemptJob < JobBase
  def initialize(build_options)
    @build_attempt_id = build_options["build_attempt_id"]
    @build_ref = build_options["build_ref"]
    @build_kind = build_options["build_kind"]
    @branch = build_options["branch"]
    @test_files = build_options["test_files"]
    @repo_name = build_options["repo_name"]
    @test_command = build_options["test_command"]
    @nexus_url = build_options["nexus_url"]
    @nexus_repo_id = build_options["nexus_repo_id"]
    @upload_artifact = build_options["upload_artifact"]
    @remote_name = build_options["remote_name"]
    @repo_url = build_options["repo_url"]
    @timeout = build_options["timeout"]
    @options = build_options["options"]
  end

  def sha
    @build_ref
  end

  def logger
    Kochiku::Worker.logger
  end

  def perform
    logger.info("Build Attempt #{@build_attempt_id} perform starting")
    build_status = signal_build_is_starting
    return if build_status == :aborted

    Kochiku::Worker::GitRepo.inside_copy(@repo_name, @remote_name, @repo_url, @build_ref, @branch) do
      begin
        result = run_tests(@build_kind, @test_files, @test_command, @timeout, @options) ? :passed : :failed
        if result == :passed && @upload_artifact
          @test_files.each { |file| upload_artifact(file) }
        end
        signal_build_is_finished(result)
      ensure
        collect_logs(Kochiku::Worker.build_strategy.log_files_glob)
      end
    end
    logger.info("Build Attempt #{@build_attempt_id} perform finished")
  end

  def collect_logs(file_glob)
    benchmark("Build Attempt #{@build_attempt_id} collecting logs") do
      Dir[*file_glob].each do |path|
        if File.file?(path) && !File.zero?(path)
          Cocaine::CommandLine.new("gzip", path).run
          path += '.gz'
          upload_log_file(File.new(path))
        end
      end
    end
  end

  def on_exception(e)
    if e.instance_of? Kochiku::Worker::GitRepo::RefNotFoundError
      handle_git_ref_not_found(e)
      # avoid calling super because this does not need to go into the failed queue
      return
    end

    logger.error("Exception occurred during build (#{@build_attempt_id}):")
    logger.error(e)

    message = StringIO.new
    message.puts(e.message)
    message.puts(e.backtrace)
    message.rewind
    # Need to override path method for RestClient to upload this correctly
    def message.path
      'error.txt'
    end

    upload_log_file(message)

    # Signal build is errored after error.txt is uploaded so we can
    # reference error.txt in the build_attempt observer on the master.
    signal_build_is_finished(:errored)

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
        logger.error("Start notification of build (#{@build_attempt_id}) failed: #{e.message}")
        raise
      end
    end
  end

  def signal_build_is_finished(result)
    benchmark("Signal build attempt #{@build_attempt_id} finished") do
      build_finish_url = "http://#{Kochiku::Worker.settings.build_master}/build_attempts/#{@build_attempt_id}/finish"

      begin
        RestClient::Request.execute(:method => :post, :url => build_finish_url, :payload => {:state => result}, :headers => {:accept => :json}, :timeout => 60, :open_timeout => 60)
      rescue Errno::EHOSTUNREACH
        tries = (tries || 0) + 1
        if tries < 2
          sleep 1
          retry
        end
      rescue RestClient::Exception => e
        logger.error("Finish notification of build (#{@build_attempt_id}) failed: #{e.message}")
        raise
      end
    end
  end

  def upload_artifact(mvn_module)
    return unless @build_kind == 'maven'
    benchmark("Uploading artifact for #{mvn_module}") do
      shaded_jar = Dir.glob("#{mvn_module}/target/*-shaded.jar").first
      command = ['mvn', 'org.apache.maven.plugins:maven-deploy-plugin:2.7:deploy-file',
                 "-Durl=#{@nexus_url}",
                 "-Dfile=#{shaded_jar}",
                 "-Dversion=#{sha}",
                 '-DupdateReleaseInfo=true',
                 "-DpomFile=#{mvn_module}/pom.xml",
                 "-DrepositoryId=#{@nexus_repo_id}",
                 "-Dclassifier=shaded"
      ]

      BuildStrategy.execute_with_timeout(command, @timeout, "log/artifact-upload.log")
    end
  end

  def upload_log_file(file)
    log_artifact_upload_url = "http://#{Kochiku::Worker.settings.build_master}/build_attempts/#{@build_attempt_id}/build_artifacts"

    begin
      RestClient::Request.execute(:method => :post, :url => log_artifact_upload_url, :payload => {:build_artifact => {:log_file => file}}, :headers => {:accept => :xml}, :timeout => 60 * 5)
    rescue Errno::EHOSTUNREACH
      tries = (tries || 0) + 1
      if tries < 2
        sleep 1
        retry
      end
    rescue RestClient::Exception => e
      logger.error("Upload of artifact (#{file.to_s}) failed: #{e.message}")
    end
  end

  def handle_git_ref_not_found(exception)
    logger.warn("#{exception.class} during build attempt (#{@build_attempt_id}):")
    logger.warn(exception.message)

    message = StringIO.new
    message.puts(exception.message)
    message.puts(exception.backtrace)
    message.rewind
    # Need to override path method for RestClient to upload this correctly
    def message.path
      'aborted.txt'
    end

    upload_log_file(message)

    signal_build_is_finished(:aborted)
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
