require 'socket'
require 'rest-client'
require 'retryable'

class BuildAttemptJob < JobBase
  def initialize(build_options)
    @build_attempt_id = build_options["build_attempt_id"]
    @build_ref = build_options["build_ref"]
    @build_kind = build_options["build_kind"]
    @branch = build_options["branch"]
    @test_files = build_options["test_files"]
    @repo_name = build_options["repo_name"]
    @test_command = build_options["test_command"]
    @remote_name = build_options["remote_name"]
    @repo_url = build_options["repo_url"]
    @timeout = build_options["timeout"]
    @options = build_options["options"] || {}
    @kochiku_env = build_options["kochiku_env"]
  end

  def sha
    @build_ref
  end

  def logger
    Kochiku::Worker.logger
  end

  def perform
    logger.info("Build Attempt #{@build_attempt_id} perform starting")
    return if signal_build_is_starting == :aborted

    Retryable.retryable(tries: 5, on: Kochiku::Worker::GitRepo::RefNotFoundError, sleep: 12) do   # wait for up to 60 seconds for the sha to be available
      Kochiku::Worker::GitRepo.inside_copy(@repo_name, @remote_name, @repo_url, @build_ref) do
        begin
          result = run_tests(@build_kind, @test_files, @test_command, @timeout, @options.merge({"git_commit" => @build_ref, "git_branch" => @branch, "kochiku_env" => @kochiku_env})) ? :passed : :failed
          signal_build_is_finished(result)
        ensure
          collect_logs(Kochiku::Worker.build_strategy.log_files_glob)
        end
      end
    end
    logger.info("Build Attempt #{@build_attempt_id} perform finished")
  end

  def collect_logs(file_glob)
    detected_files = Dir.glob(file_glob)
    benchmark("collecting logs (#{detected_files.join(', ')}) for BuildAttempt #{@build_attempt_id}") do
      detected_files.each do |path|
        if File.file?(path) && !File.zero?(path)
          if path =~ /log$/
            Cocaine::CommandLine.new("gzip", path).run
            path += '.gz'
          end
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
    Socket.gethostname
  end

  def run_tests(build_kind, test_files, test_command, timeout, options)
    logger.info("Running tests for #{@build_attempt_id}")
    Kochiku::Worker.build_strategy.execute_build(build_kind, test_files, test_command, timeout, options)
  end

  def with_http_retries(&block)
    # 3 retries; sleep for 15, 45, and 60 seconds between tries
    backoff_proc = lambda { |n| [15, 45, 60][n] }

    Retryable.retryable(tries: 4, on: [Errno::EHOSTUNREACH, RestClient::Exception, SocketError], sleep: backoff_proc) do
      block.call
    end
  end

  def signal_build_is_starting
    result = nil
    benchmark("Signal build attempt #{@build_attempt_id} starting") do
      build_start_url = "#{url_base}/start"
      with_http_retries do
        result = RestClient::Request.execute(method: :post,
                                             url: build_start_url,
                                             payload: { builder: hostname },
                                             headers: { accept: :json })
      end
    end
    JSON.parse(result)["build_attempt"]["state"].to_sym
  end

  def signal_build_is_finished(result)
    benchmark("Signal build attempt #{@build_attempt_id} finished") do
      build_finish_url = "#{url_base}/finish"
      with_http_retries do
        RestClient::Request.execute(method: :post,
                                    url: build_finish_url,
                                    payload: { state: result },
                                    headers: { accept: :json },
                                    timeout: 60,
                                    open_timeout: 60)
      end
    end
  end

  def upload_log_file(file)
    log_artifact_upload_url = "#{url_base}/build_artifacts"
    with_http_retries do
      file.rewind
      RestClient::Request.execute(method: :post,
                                  url: log_artifact_upload_url,
                                  payload: { build_artifact: { log_file: file.clone } },
                                  headers: { accept: :xml },
                                  timeout: 60 * 5)
    end
  rescue Errno::EHOSTUNREACH, RuntimeError => e
    # log exception and continue. A failed log file upload should not interrupt the BuildAttempt
    logger.error("Upload of artifact (#{file.to_s}) failed: #{e.message}")
  ensure
    file.close
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

  def url_base
    "#{Kochiku::Worker.settings.kochiku_web_server_protocol}://" +
      "#{Kochiku::Worker.settings.kochiku_web_server_host}/build_attempts/#{@build_attempt_id}"
  end
end
