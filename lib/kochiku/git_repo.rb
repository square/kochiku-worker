require 'cocaine'

module Kochiku
  module Worker
    class GitRepo
      class RefNotFoundError < StandardError; end
      WORKING_DIR = File.expand_path(File.join(File.dirname(__FILE__), '..', '..', 'tmp', 'build-partition'))

      class << self
        def inside_copy(cached_repo_name, remote_name, repo_url, sha, branch)
          cached_repo_path = File.join(WORKING_DIR, cached_repo_name)

          if !File.directory?(cached_repo_path)
            clone_repo(repo_url, cached_repo_path)
          end
          Dir.chdir(cached_repo_path) do
            # update the cached repo
            remote_list = `git remote -v | grep #{remote_name}`
            unless remote_list.include?(remote_name)
              run! "git remote add #{remote_name} #{repo_url}"
            end
            synchronize_with_remote(remote_name, sha, branch)
            # Update the master ref so that scripts may treat master build differently than branch build
            synchronize_with_remote(remote_name, sha, 'master') unless branch == 'master'
            #TODO: doing this here is questionable - this may not work for forks
            Cocaine::CommandLine.new("git submodule update", "--init --quiet").run
          end

          Dir.mktmpdir(nil, WORKING_DIR) do |dir|
            # clone local repo (fast!)
            run! "git clone #{cached_repo_path} #{dir}"

            Dir.chdir(dir) do
              raise RefNotFoundError.new("Build Ref #{sha} not found in #{repo_url}") unless system("git rev-list --quiet -n1 #{sha}")
              run! "git checkout --quiet #{sha}"

              run! "git submodule --quiet init"
              # redirect the submodules to the cached_repo
              submodules = `git config --get-regexp "^submodule\\..*\\.url$"`
              submodules.each_line do |config_line|
                submodule_path = config_line.match(/submodule\.(.*?)\.url/)[1]
                `git config --replace-all submodule.#{submodule_path}.url "#{cached_repo_path}/#{submodule_path}"`
              end

              run! "git submodule --quiet update"

              yield
            end
          end
        end

        def create_working_dir
          FileUtils.mkdir_p(WORKING_DIR)
        end

        private

        def run!(cmd)
          unless system(cmd)
            raise "non-0 exit code #{$?} returned from [#{cmd}]"
          end
        end

        def clone_repo(repo_url, cached_repo_path)
          Cocaine::CommandLine.new("git clone", "--recursive #{repo_url} #{cached_repo_path}").run
        end

        def synchronize_with_remote(name, sha, branch = nil)
          refspec = branch.to_s.empty? ? "" : "+#{branch}"
          Cocaine::CommandLine.new("git fetch", "--quiet --prune --no-tags #{name} #{refspec}").run
          # Check that we got the sha we are expecting
          Cocaine::CommandLine.new("git rev-list", "--quiet -n1 #{sha}").run
        rescue Cocaine::ExitStatusError => e
          # likely caused by another 'git fetch' that is currently in progress. Wait a few seconds and try again
          tries = (tries || 0) + 1
          if tries < 3
            Kochiku::Worker.logger.warn(e)
            sleep(15 * tries)
            retry
          else
            raise e
          end
        end
      end
    end
  end
end
