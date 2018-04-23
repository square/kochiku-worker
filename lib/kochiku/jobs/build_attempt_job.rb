require 'socket'
require 'rest-client'
require 'retryable'

class BuildAttemptJob < JobBase
  include Benchmark

  def initialize(build_options)
    @build_attempt_id = build_options["build_attempt_id"]
    @build_ref = build_options["build_ref"]
    @build_kind = build_options["build_kind"]
    @branch = build_options["branch"]
    @test_files = build_options["test_files"]
    @test_command = build_options["test_command"]
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
    redis_client = Kochiku::Worker.redis_client
    redis_key = "kochiku_worker:#{hostname}:build_attempt"
    redis_client.set(redis_key, @build_attempt_id, ex: 60 * 60)

    logstreamer_port = Kochiku::Worker.settings['logstreamer_port']
    launch_logstreamer(logstreamer_port)

    logger.info("Build Attempt #{@build_attempt_id} perform starting")

    return if signal_build_is_starting(logstreamer_port) == :aborted

    Retryable.retryable(tries: 5, on: Kochiku::Worker::GitRepo::RefNotFoundError, sleep: 12) do   # wait for up to 60 seconds for the sha to be available
      Kochiku::Worker::GitRepo.inside_copy(@repo_url, @build_ref) do
        begin
          hardlink_log(Kochiku::Worker.build_strategy.stdout_log_file)
          options = @options.merge("git_commit" => @build_ref, "git_branch" => @branch, "kochiku_env" => @kochiku_env)
          result = run_tests(@build_kind, @test_files, @test_command, @timeout, options) ? :passed : :failed
          signal_build_is_finished(result)
          redis_client.del(redis_key)
        ensure
          collect_logs(Kochiku::Worker.build_strategy.log_files_glob)
        end
      end
    end
    logger.info("Clean up build environment")
    clean_orphan_processes
    logger.info("Build Attempt #{@build_attempt_id} perform finished")
  end

  # attempts to launch logstreamer on specified port. Returns true on success, false otherwise.
  def launch_logstreamer(port)
    logstreamer_cmd = "#{worker_base_dir}/logstreamer/logstreamer -p #{port}"
    pid = Process.spawn(logstreamer_cmd, out: [log_file, "a"], err: [:child, :out], pgroup: true)
    Process.detach(pid)
  end

  def collect_logs(file_glob)
    detected_files = Dir.glob(file_glob)
    benchmark("collecting logs (#{detected_files.join(', ')}) for Build Attempt #{@build_attempt_id}") do
      detected_files.each do |path|
        if File.file?(path) && !File.zero?(path)
          if path =~ /log$/
            Cocaine::CommandLine.new("gzip", "-f :path").run(path: path) # -f is because we need to break the hardlink
            path += '.gz'
          end
          upload_log_file(File.new(path))
        end
      end
    end
  end

  def on_exception(e)
    if e.instance_of? Kochiku::Worker::GitRepo::RefNotFoundError ||
      (e.instance_of? Cocaine::ExitStatusError && e.message.include?("Invalid symmetric difference expression"))
      handle_git_ref_not_found(e)
      # avoid calling super because this does not need to go into the failed queue
      return
    end

    logger.error("Exception occurred during Build Attempt (#{@build_attempt_id}):")
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
    Kochiku::Worker.build_strategy.execute_build(@build_attempt_id, build_kind, test_files, test_command, timeout, options)
  end

  def clean_orphan_processes
    clean_script = "#{worker_base_dir}/bin/clean_orphan"
    Bundler.with_clean_env do
      Process.spawn(clean_script, out: [log_file, "a"], err: [:child, :out], pgroup: true)
    end
  end

  # log persistence needed for logstreamer
  def hardlink_log(log)
    FileUtils.mkdir_p("log")
    FileUtils.touch(log)

    FileUtils.mkdir_p("#{worker_base_dir}/logstreamer/logs/#{@build_attempt_id}/")
    FileUtils.ln(log, "#{worker_base_dir}/logstreamer/logs/#{@build_attempt_id}/stdout.log")
  end

  def log_file
    'log/stdout.log'
  end

  def worker_base_dir
    '/data/app/kochiku-worker/current'
  end

  def with_http_retries(&block)
    # 3 retries; sleep for 15, 45, and 60 seconds between tries
    backoff_proc = lambda { |n| [15, 45, 60][n] }

    Retryable.retryable(tries: 4, on: [Errno::ECONNRESET, Errno::EHOSTUNREACH, RestClient::Exception, SocketError], sleep: backoff_proc) do
      block.call
    end
  end

  def signal_build_is_starting(logstreamer_port)
    result = nil
    benchmark("Signal Build Attempt #{@build_attempt_id} starting") do
      build_start_url = "#{url_base}/start"
      payload = {:builder => hostname}
      payload[:instance_type] = Kochiku::Worker.instance_type if Kochiku::Worker.instance_type
      payload[:logstreamer_port] = logstreamer_port if logstreamer_port

      with_http_retries do
        result = RestClient::Request.execute(method: :post,
                                             url: build_start_url,
                                             payload: payload,
                                             headers: { accept: :json })
      end
    end
    JSON.parse(result)["build_attempt"]["state"].to_sym
  end

  def signal_build_is_finished(result)
    benchmark("Signal Build Attempt #{@build_attempt_id} finished") do
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
    upload_credentials = with_http_retries do
      JSON.parse(
        RestClient.get(
          "#{url_base}/build_artifacts/new",
          params: { build_artifact: { log_file: File.basename(file.path) } }
        )
      )
    end

    with_http_retries do
      file.rewind

      RestClient::Request.execute(
        method: :post,
        url: upload_credentials['url'],
        payload: upload_credentials['fields'].update('file' => file.clone),
        timeout: 5 * 60
      )
    end

    with_http_retries do
      RestClient::Request.execute(
        method: :post,
        url: "#{url_base}/build_artifacts",
        payload: { build_artifact: { log_file: File.basename(file.path) } }
      )
    end
  rescue Errno::ECONNRESET, Errno::EHOSTUNREACH, RestClient::Exception, RuntimeError => e
    # log exception and continue. A failed log file upload should not interrupt the BuildAttempt
    logger.error("Upload of artifact (#{file.path}) for Build Attempt #{@build_attempt_id} failed: #{e.message}")
  ensure
    file.close
  end

  def handle_git_ref_not_found(exception)
    logger.warn("#{exception.class} during Build Attempt (#{@build_attempt_id}):")
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

  def url_base
    "#{Kochiku::Worker.settings.kochiku_web_server_protocol}://" +
      "#{Kochiku::Worker.settings.kochiku_web_server_host}/build_attempts/#{@build_attempt_id}"
  end
end
