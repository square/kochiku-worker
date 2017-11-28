require 'cocaine'

module GitStrategy
  # Keeps a full clone locally on the worker and uses it as a cache.
  # Uses git clone --local for fast clones and checkouts. Since caches are kept
  # in the same directory as temporary checkouts, they're guaranteed to be on the
  # same filesystem and git can hardlink objects under the hood.
  #
  # Scaling:
  # Git operations are required to update the local cache, and git operations
  # are cpu-intensive on the server side. Eventually the server will become constrained
  # on cpu. At that point, a read-only mirror can be created to absorb the load of the
  # worker cluster, or you can switch to the shared cache strategy.
  #
  # When to use:
  # This is the most basic and default git strategy. Use it when you aren't running
  # enough workers to overwhelm your primary git server or git mirror.
  class LocalCache
    class << self
      def clone_and_checkout(repo_url, commit)
        tmp_dir = Dir.mktmpdir(nil, Kochiku::Worker::GitRepo::WORKING_DIR)

        repo_path = repo_url.match(/.+?([^:\/]+\/[^\/]+)\.git\z/)[1]
        cached_repo_path = File.join(Kochiku::Worker::GitRepo::WORKING_DIR, repo_path)
        synchronize_cache_repo(cached_repo_path, repo_url, commit)

        # clone local repo (fast!)
        run! "git clone #{cached_repo_path} #{tmp_dir}"

        Dir.chdir(tmp_dir) do
          run! "git checkout --quiet #{commit}"

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

        tmp_dir
      end

      private

      def synchronize_cache_repo(cached_repo_path, repo_url, commit)
        if !Dir.exist?(cached_repo_path)
          clone_repo(repo_url, cached_repo_path)
        end
        Dir.chdir(cached_repo_path) do
          harmonize_remote_url(repo_url)
          run_git_fetch

          if !commit.nil? && !system("git rev-list --quiet -n1 #{commit}")
            raise Kochiku::Worker::GitRepo::RefNotFoundError.new("Build Ref #{commit} not found in #{repo_url}")
          end

          Cocaine::CommandLine.new("git submodule update", "--init --quiet").run
        end
      end

      def run!(cmd)
        unless system(cmd)
          raise "non-0 exit code #{$?} returned from [#{cmd}]"
        end
      end

      def clone_repo(repo_url, cached_repo_path)
        Cocaine::CommandLine.new("git clone", "--recursive #{repo_url} #{cached_repo_path}").run
      end

      def run_git_fetch
        exception_cb = Proc.new do |exception|
          Kochiku::Worker.logger.warn(exception)
        end

        # likely caused by another 'git fetch' that is currently in progress. Wait a few seconds and try again
        Retryable.retryable(tries: 3, on: Cocaine::ExitStatusError, sleep: lambda { |n| 15*n }, exception_cb: exception_cb) do
          Cocaine::CommandLine.new("git fetch", "--quiet --prune --no-tags").run
        end
      end

      # Update the remote url for the git repository if it has changed
      def harmonize_remote_url(expected_url)
        remote_url = Cocaine::CommandLine.new("git config --get remote.origin.url").run.chomp
        if remote_url != expected_url
          puts "#{remote_url.inspect} does not match #{expected_url.inspect}. Updating it."
          Cocaine::CommandLine.new("git remote", "set-url origin #{expected_url}").run
        end
      end
    end
  end
end
