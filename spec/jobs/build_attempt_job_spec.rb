require 'spec_helper'
require 'fileutils'
require 'json'

describe BuildAttemptJob do
  let(:master_host) { Kochiku::Worker.settings.kochiku_web_server_protocol +
                      "://" + Kochiku::Worker.settings.kochiku_web_server_host }
  let(:build_attempt_id) { "42" }
  let(:build_part_kind) { "test" }
  let(:build_ref) { "123abc" }
  let(:test_files) { ["/foo/1.test", "foo/baz/a.test", "foo/baz/b.test"] }
  let(:build_options) { {
      "build_attempt_id" => build_attempt_id,
      "build_ref" => build_ref,
      "build_kind" => build_part_kind,
      "test_files" => test_files,
      "repo_name" => 'local-cache',
      "remote_name" => "origin",
      "test_command" => "script/ci worker",
      "repo_url" => "git@github.com:square/kochiku-worker.git"
  } }

  subject { BuildAttemptJob.new(build_options) }

  before do
    FileUtils.mkdir_p(File.join(File.dirname(__FILE__), "..", "..", "tmp", "build-partition", "local-cache"))
  end

  describe "#perform" do
    before do
      allow(GitStrategy::LocalCache).to receive(:system).and_return(true)
    end

    context "build_attempt has been aborted" do
      it "should return without running the tests" do
        stub_request(:post, "#{master_host}/build_attempts/#{build_attempt_id}/start").to_return(:body => {'build_attempt' => {'state' => 'aborted'}}.to_json)

        expect(subject).not_to receive(:run_tests)
        subject.perform
      end
    end

    it "sets the builder on its build attempt" do
      hostname = "i-am-a-compooter"
      allow(subject).to receive(:run_tests)
      allow(subject).to receive(:hostname).and_return(hostname)
      stub_request(:post, "#{master_host}/build_attempts/#{build_attempt_id}/start").to_return(:body => {'build_attempt' => {'state' => 'running'}}.to_json)
      stub_request(:post, "#{master_host}/build_attempts/#{build_attempt_id}/finish")

      subject.perform
      expect(WebMock).to have_requested(:post, "#{master_host}/build_attempts/#{build_attempt_id}/start").with(:body => {"builder"=> hostname})
    end

    context "build is successful" do
      before { allow(subject).to receive(:run_tests).and_return(true) }

      it "creates a build result with a passed result" do
        stub_request(:post, "#{master_host}/build_attempts/#{build_attempt_id}/start").to_return(:body => {'build_attempt' => {'state' => 'running'}}.to_json)
        stub_request(:post, "#{master_host}/build_attempts/#{build_attempt_id}/finish")

        subject.perform

        expect(WebMock).to have_requested(:post, "#{master_host}/build_attempts/#{build_attempt_id}/finish").with(:body => {"state"=> "passed"})
      end
    end

    context "build is unsuccessful" do
      before { allow(subject).to receive(:run_tests).and_return(false) }

      it "creates a build result with a failed result" do
        stub_request(:post, "#{master_host}/build_attempts/#{build_attempt_id}/start").to_return(:body => {'build_attempt' => {'state' => 'running'}}.to_json)
        stub_request(:post, "#{master_host}/build_attempts/#{build_attempt_id}/finish")

        subject.perform

        expect(WebMock).to have_requested(:post, "#{master_host}/build_attempts/#{build_attempt_id}/finish").with(:body => {"state"=> "failed"})
      end
    end

    context "an exception occurs" do
      class FakeTestError < StandardError; end

      it "sets the build attempt state to errored" do
        stub_request(:post, "#{master_host}/build_attempts/#{build_attempt_id}/start").to_return(:body => {'build_attempt' => {'state' => 'running'}}.to_json)
        stub_request(:post, "#{master_host}/build_attempts/#{build_attempt_id}/build_artifacts")
        stub_request(:post, "#{master_host}/build_attempts/#{build_attempt_id}/finish").to_return(:head => :ok)

        expect(subject).to receive(:run_tests).and_raise(FakeTestError.new('something went wrong'))
        expect(BuildAttemptJob).to receive(:new).and_return(subject)
        allow(Kochiku::Worker.logger).to receive(:error)

        expect { BuildAttemptJob.perform(build_options) }.to raise_error(FakeTestError)

        expect(WebMock).to have_requested(:post, "#{master_host}/build_attempts/#{build_attempt_id}/build_artifacts").with(
          :headers => {'Content-Type' => /multipart\/form-data/},
          :body => /something went wrong/
        )
        expect(WebMock).to have_requested(:post, "#{master_host}/build_attempts/#{build_attempt_id}/finish").with(:body => {"state" => "errored"})
      end

      context "and its GitRepo::RefNotFoundError" do
        it "sets the build attempt state to aborted" do
          stub_request(:post, "#{master_host}/build_attempts/#{build_attempt_id}/start").to_return(:body => {'build_attempt' => {'state' => 'running'}}.to_json)
          stub_request(:post, "#{master_host}/build_attempts/#{build_attempt_id}/build_artifacts")
          stub_request(:post, "#{master_host}/build_attempts/#{build_attempt_id}/finish").to_return(:head => :ok)

          expect(subject).to receive(:run_tests).and_raise(Kochiku::Worker::GitRepo::RefNotFoundError.new)
          expect(BuildAttemptJob).to receive(:new).and_return(subject)
          allow(Kochiku::Worker.logger).to receive(:warn)

          expect { BuildAttemptJob.perform(build_options) }.to_not raise_error

          expect(WebMock).to have_requested(:post, "#{master_host}/build_attempts/#{build_attempt_id}/build_artifacts")
          expect(WebMock).to have_requested(:post, "#{master_host}/build_attempts/#{build_attempt_id}/finish").with(:body => {"state" => "aborted"})
        end
      end
    end
  end

  describe "#collect_logs" do
    before do
      allow(Cocaine::CommandLine).to receive(:new).with("gzip", anything).and_call_original
      stub_request(:any, /#{master_host}.*/)
    end

    it "posts the local build logs back to the master server" do
      Dir.mktmpdir do |dir|
        Dir.chdir(dir) do
          wanted_logs = ['a.wantedlog', 'b.wantedlog', 'd/c.wantedlog']

          FileUtils.mkdir 'd'
          (wanted_logs + ['e.unwantedlog']).each do |file_path|
            File.open(file_path, 'w') do |file|
              file.puts "Carrierwave won't save blank files"
            end
          end

          subject.collect_logs('**/*.wantedlog')

          wanted_logs.each do |artifact|
            log_name = File.basename(artifact)
            expect(WebMock).to have_requested(:post, "#{master_host}/build_attempts/#{build_attempt_id}/build_artifacts").with { |req| req.body.include?(log_name) }
          end
        end
      end
    end

    it "should not attempt to save blank files" do
      Dir.mktmpdir do |dir|
        Dir.chdir(dir) do
          log_name = 'empty.log'
          system("touch #{log_name}")
          subject.collect_logs('*.log')
          expect(WebMock).not_to have_requested(:post, "#{master_host}/build_attempts/#{build_attempt_id}/build_artifacts").with { |req| req.body.include?(log_name) }
        end
      end
    end

    it "should be able to retry, even if the IO object has been closed" do
      stub_request(:post, "#{master_host}/build_attempts/#{build_attempt_id}/build_artifacts").to_return(:status => 500, :body => "", :headers => {})
      allow(subject).to receive(:sleep)

      Dir.mktmpdir do |dir|
        Dir.chdir(dir) do
          log_name = 'a.log'

          File.open(log_name, 'w') do |file|
            file.puts "Carrierwave won't save blank files"
          end

          expect {
            subject.collect_logs('**/*.log')
          }.not_to raise_error  # specifically, IOError

          expect(WebMock).to have_requested(:post, "#{master_host}/build_attempts/#{build_attempt_id}/build_artifacts").times(4)
        end
      end
    end
  end

  describe "#with_http_retries" do
    before do
      allow(subject).to receive(:sleep)
    end

    it "should raise after retrying" do
      expect {
        subject.send(:with_http_retries) do
          raise Errno::EHOSTUNREACH
        end
      }.to raise_error(Errno::EHOSTUNREACH)
    end
  end
end
