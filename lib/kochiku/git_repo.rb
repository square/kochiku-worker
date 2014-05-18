require 'cocaine'

module Kochiku
  module Worker
    class GitRepo
      class RefNotFoundError < StandardError; end

      WORKING_DIR = File.expand_path(File.join(File.dirname(__FILE__), '..', '..', 'tmp', 'build-partition'))

      class << self
        def inside_copy(cached_repo_name, remote_name, repo_url, sha, branch)
          Dir.mktmpdir(nil, WORKING_DIR) do |dir|
            case Kochiku::Worker.settings.git_strategy
              when 'localcache'
                GitStrategy::LocalCache.clone_and_checkout(dir, cached_repo_name, remote_name, repo_url, sha, branch)
              when 'sharedcache'
                GitStrategy::SharedCache.clone_and_checkout(dir, repo_url, branch)
              else
                raise 'unknown git strategy'
            end

            Dir.chdir(dir) do
              yield
            end
          end
        end
      end
    end
  end
end
