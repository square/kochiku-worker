namespace :kochiku do
  namespace :worker do
    task :resque_setup do
      require 'kochiku/worker'
    end

    desc "Setup a development environment to run a kochiku worker. Use capistrano for remote hosts"
    task :setup do
      tmp_dir = File.expand_path(File.join(File.dirname(__FILE__), '..', 'tmp', 'build-partition', 'web-cache'))
      log_dir = File.expand_path(File.join(File.dirname(__FILE__), '..', 'log'))

      unless File.exists?(tmp_dir)
        FileUtils.mkdir_p tmp_dir
        `git clone --recursive git@git.squareup.com:square/web.git #{tmp_dir}`
      end

      FileUtils.mkdir_p(log_dir)
    end
  end
end
