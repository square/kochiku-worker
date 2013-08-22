namespace :kochiku do
  namespace :worker do
    desc "Setup a local development environment to run a kochiku worker. Use capistrano for remote hosts"
    task :setup do
      tmp_dir = File.expand_path(File.join(File.dirname(__FILE__), '..', 'tmp', 'build-partition'))
      log_dir = File.expand_path(File.join(File.dirname(__FILE__), '..', 'log'))

      FileUtils.mkdir_p(tmp_dir)
      FileUtils.mkdir_p(log_dir)
    end
  end
end
