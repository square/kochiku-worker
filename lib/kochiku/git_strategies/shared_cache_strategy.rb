module GitStrategy
  # Uses alternate object stores to share object stores across worker nodes. This uses
  # git clone --shared for fast clones and checkouts. Repos are cloned
  # from a central location, which is typically an NFS mount on the workers.
  #
  # Scaling:
  # Unlike cloning over the git protocol, which is very cpu-intensive, this strategy
  # scales with available bandwidth on the server. Luckily, bandwidth use is mitigated somewhat
  # when using NFS thanks to client-side buffer cache. If you overwhelm the server,
  # get a bigger NIC or consider implementing improvement #1.
  #
  # When to use:
  # Use the shared strategy when you have enough workers to overwhelm your
  # normal git server and/or mirrors.
  #
  # Possible improvements:
  # 1. Add multiple shared roots and choose randomly between them. Poor man's client side load balancing.
  # 2. For repos that are very large when checked out, a git clean -dfx and git checkout instead of a new
  #    tmpdir would reduce disk i/o for a noticeable improvement.
  class SharedCache
    class << self
      def clone_and_checkout(tmp_dir, repo_url, commit)
        shared_repo_dir = File.join(Kochiku::Worker.settings.git_shared_root, repo_url.match(/.+?([^\/]+\/[^\/]+\.git)/)[1])
        raise 'cannot find repo in shared repos' unless Dir.exists?(shared_repo_dir)

        # check that commit exists
        Dir.chdir(shared_repo_dir) do
          begin
            Cocaine::CommandLine.new('git', 'rev-list --quiet -n1 :commit').run(commit: commit)
          rescue Cocaine::ExitStatusError
            raise Kochiku::Worker::GitRepo::RefNotFoundError
          end
        end

        # clone
        Cocaine::CommandLine.new('git', 'clone --quiet --shared --no-checkout :repo :dir').run(repo: shared_repo_dir, dir: tmp_dir)

        Dir.chdir(tmp_dir) do
          # checkout
          Cocaine::CommandLine.new('git', 'checkout --quiet :commit').run(commit: commit)

          # init submodules
          Cocaine::CommandLine.new('git', 'submodule --quiet init').run

          # update submodules. attempt to use references. best-effort.
          submodules = Cocaine::CommandLine.new('git', 'config --get-regexp "^submodule\..*\.url$"', expected_outcodes: [0,1]).run
          submodules.each_line do |submodule|
            _, path, url = submodule.match(/^submodule\.(.+?)\.url .+?([^\/]+\/[^\/]+\.git)$/).to_a
            shared_repo_dir = File.join(Kochiku::Worker.settings.git_shared_root, url || 'does-not-exist')

            if Dir.exists?(shared_repo_dir)
              Cocaine::CommandLine.new('git', 'submodule --quiet update --reference :shared :path').run(shared: shared_repo_dir, path: path)
            else
              Cocaine::CommandLine.new('git', 'submodule --quiet update :path').run(path: path)
            end
          end
        end
      end
    end
  end
end