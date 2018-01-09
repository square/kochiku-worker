require 'cocaine'

module Kochiku
  module Worker
    class GitRepo
      class RefNotFoundError < StandardError; end

      WORKING_DIR = File.expand_path(File.join(File.dirname(__FILE__), '..', '..', 'tmp', 'build-partition'))

      class << self
        def inside_copy(repo_url, sha)
          dir = case Kochiku::Worker.settings.git_strategy
                when 'localcache'
                  GitStrategy::LocalCache.clone_and_checkout(repo_url, sha)
                when 'sharedcache'
                  GitStrategy::SharedCache.clone_and_checkout(repo_url, sha)
                else
                  raise 'unknown git strategy'
                end

          Dir.chdir(dir) do
            yield
          end
        ensure
          if Kochiku::Worker.settings.git_strategy == 'localcache'
            FileUtils.remove_entry(dir)
          end
        end
      end
    end
  end
end
