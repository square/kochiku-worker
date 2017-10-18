require 'spec_helper'

RSpec.describe BuildStrategy::BuildAllStrategy do
  let(:dev_null) { "2>/dev/null 1>/dev/null" }
  subject{ BuildStrategy::BuildAllStrategy.new }

  before do
    old_spawn = Process.method(:spawn)
    allow(Process).to receive(:spawn) do |*args|
      @spawned_pid = old_spawn.call(*args)
    end
    File.unlink(subject.stdout_log_file) if File.exists?(subject.stdout_log_file)

    stub_const("BuildStrategy::BuildAllStrategy::KILL_TIMEOUT", 1)
    allow(BuildStrategy).to receive(:take_jstack)
  end

  describe "#execute_with_timeout_and_kill" do
    let(:busy_wait) { "while true; do true; done"}
    let(:trap_sigterm) { "trap 'echo SIGTERM blocked' 15"}
    let(:log) { IO.readlines(subject.stdout_log_file) }
    let(:process_kill_message) { "******** The following process(es) taking too long, Kochiku killing NOW ************\n" }

    it "should not claim to have killed when it didn't" do
      subject.execute_with_timeout_and_kill "true", 0.1

      expect(log).not_to include(process_kill_message)
    end

    it "should return true if it succeeds" do
      expect(subject.execute_with_timeout_and_kill("true #{dev_null}", 0.1)).to eq(true)
    end

    it "should return false if it fails" do
      expect(subject.execute_with_timeout_and_kill("false #{dev_null}", 0.1)).to eq(false)
    end

    it "should raise a ErrorFoundInLogError for known errors in output of a failed build" do
      expect {
        subject.execute_with_timeout_and_kill("false # couldn't find resque worker", 0.5)
      }.to raise_error(BuildStrategy::BuildAllStrategy::ErrorFoundInLogError)
    end

    it "won't raise ErrorFoundInLogError when the build passes" do
      expect {
        subject.execute_with_timeout_and_kill("true # couldn't find resque worker", 0.5)
      }.to_not raise_error
    end

    context "No children processes spawned" do
      context "process times out" do
        context "SIGTERM not trapped" do
          it "should kill the command if it takes too long" do
            start_time = Time.now
            expect {
              subject.execute_with_timeout_and_kill("sleep 300 #{dev_null}", 0.1)
            }.to_not raise_error
            expect(Time.now - start_time).to be_within(0.3).of(0.1)
            expect {
              Process.kill(0, @spawned_pid)
            }.to raise_error(Errno::ESRCH)

            expect(log).to include(process_kill_message)
            expect(log).to include("sleep 300")
          end
        end
        context "SIGTERM trapped" do
          it "should kill process even if SIGTERM trapped" do
            expect {
              subject.execute_with_timeout_and_kill(
                "
                  #{trap_sigterm}
                  #{busy_wait}
                ", 0.1)
            }.to_not raise_error

            expect {
              Process.kill(-15, @spawned_pid)
            }.to raise_error(Errno::ESRCH)
          end
        end
      end
    end

    context "Children processses spawned" do
      context "head process ends normally" do
        context "spawned processes do not trap SIGTERM" do
          it "should kill all child processes" do
            expect {
              subject.execute_with_timeout_and_kill(
                "
                  function2_to_fork() {
                    #{trap_sigterm}
                    #{busy_wait}
                  }

                  function3_to_fork() {
                    #{busy_wait}
                  }

                  function_to_fork() {
                    function2_to_fork &
                    function3_to_fork &
                    sleep 100
                  }

                  function_to_fork &
                  true
                ", 0.1)
            }.to_not raise_error

            expect {
              Process.kill(-15, @spawned_pid)
            }.to raise_error(Errno::ESRCH)

            expect(log).to include(process_kill_message)
            expect(log).to include("sleep 100")
          end
        end

        context "some spawned processes trap SIGTERM" do
          it "should kill all child processes" do
            expect {
              subject.execute_with_timeout_and_kill(
                "
                  function2_to_fork() {
                    #{trap_sigterm}
                    #{busy_wait}
                  }

                  function3_to_fork() {
                    #{busy_wait}
                  }

                  function_to_fork() {
                    function2_to_fork &
                    function3_to_fork &
                    sleep 100
                  }

                  function_to_fork &
                  true
                ", 0.1)
            }.to_not raise_error

            expect {
              Process.kill(-15, @spawned_pid)
            }.to raise_error(Errno::ESRCH)

            expect(log).to include(process_kill_message)
            expect(log).to include("sleep 100")
          end
        end
      end

      context "head process times out" do
        context "spawned processes do not trap SIGTERM" do
          it "should kill all child processes" do
            expect {
              subject.execute_with_timeout_and_kill(
                "
                  function2_to_fork() {
                    #{busy_wait}
                  }

                  function3_to_fork() {
                    #{busy_wait}
                  }

                  function_to_fork() {
                    function2_to_fork &
                    function3_to_fork &
                    sleep 100
                  }

                  function_to_fork &
                  sleep 300
                ", 0.1)
            }.to_not raise_error

            expect {
              Process.kill(-15, @spawned_pid)
            }.to raise_error(Errno::ESRCH)
          end
        end
        context "some spawned processes trap SIGTERM" do
          it "should kill all child processes" do
            expect {
              subject.execute_with_timeout_and_kill(
                "
                  function2_to_fork() {
                    #{trap_sigterm}
                    #{busy_wait}
                  }

                  function3_to_fork() {
                    #{busy_wait}
                  }

                  function_to_fork() {
                    function2_to_fork &
                    function3_to_fork &
                    sleep 100
                  }

                  function_to_fork &
                  #{busy_wait}
                ", 0.1)
            }.to_not raise_error

            expect {
              Process.kill(-15, @spawned_pid)
            }.to raise_error(Errno::ESRCH)
          end
        end
      end
    end
  end
end
