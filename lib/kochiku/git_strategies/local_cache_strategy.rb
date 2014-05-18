require 'cocaine'

module GitStrategy
  class LocalCache
    class << self
      # TODO: make this conform to the same api as nfs strategy. don't need cache name, remote name, etc
      def clone_and_checkout(tmp_dir, cached_repo_name, remote_name, repo_url, sha, branch)
        cached_repo_path = File.join(Kochiku::Worker::GitRepo::WORKING_DIR, cached_repo_name)
        synchronize_cache_repo(cached_repo_path, remote_name, repo_url, sha, branch)

        # clone local repo (fast!)
        run! "git clone #{cached_repo_path} #{tmp_dir}"

        Dir.chdir(tmp_dir) do
          raise Kochiku::Worker::GitRepo::RefNotFoundError.new("Build Ref #{sha} not found in #{repo_url}") unless system("git rev-list --quiet -n1 #{sha}")
          run! "git checkout --quiet #{sha}"

          run! "git submodule --quiet init"

          submodules = `git config --get-regexp "^submodule\\..*\\.url$"`

          unless submodules.empty?
            cached_submodules = `git config --get-regexp "^submodule\\..*\\.url$"`

            # Redirect the submodules to the cached_repo
            # If the submodule was added after the initial clone of the cache
            # repo then it will not be present in the cached_repo and we fall
            # back to cloning it for each build.
            submodules.each_line do |config_line|
              if cached_submodules.include?(config_line)
                submodule_path = config_line.match(/submodule\.(.*?)\.url/)[1]
                `git config --replace-all submodule.#{submodule_path}.url "#{cached_repo_path}/#{submodule_path}"`
              end
            end

            run! "git submodule --quiet update"
          end
        end
      end

      private

      def synchronize_cache_repo(cached_repo_path, remote_name, repo_url, sha, branch)
        if !File.directory?(cached_repo_path)
          clone_repo(repo_url, remote_name, cached_repo_path)
        end
        Dir.chdir(cached_repo_path) do
          remote_url = Cocaine::CommandLine.new("git config --get remote.#{remote_name}.url").run.chomp
          if remote_url != repo_url
            puts "#{remote_url.inspect} does not match #{repo_url.inspect}. Updating it."
            Cocaine::CommandLine.new("git remote set-url #{remote_name} #{repo_url}").run
          end

          synchronize_with_remote(remote_name, branch)

          # Update the master ref so that scripts may treat master build
          # differently than branch build
          synchronize_with_remote(remote_name, 'master') unless branch == 'master'

          Cocaine::CommandLine.new("git submodule update", "--init --quiet").run
        end
      end

      def run!(cmd)
        unless system(cmd)
          raise "non-0 exit code #{$?} returned from [#{cmd}]"
        end
      end

      def clone_repo(repo_url, remote_name, cached_repo_path)
        Cocaine::CommandLine.new("git clone", "--recursive --origin #{remote_name} #{repo_url} #{cached_repo_path}").run
      end

      def synchronize_with_remote(name, branch = nil)
        refspec = branch.to_s.empty? ? "" : "+#{branch}"
        Cocaine::CommandLine.new("git fetch", "--quiet --prune --no-tags #{name} #{refspec}").run
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