Kochiku Worker
==============

Kochiku is "Build" in Japanese (according to google translate).

Kochiku consists of two pieces. There is a master process and a number of slave
workers. The slave workers check out a copy of your project into a directory
and run a subset of the tests inside of it. They then report status, any build
artifacts (logs, etc) and statistical information back to the master server.


Worker
------

### BuildPartitioningJob
Fills the queue with build part jobs. Enqueued by the master.

### BuildPartJob
Runs the tests for a particular part of the build. Updates status.

### BuildStateUpdateJob
Promotes a tag if the build is successful. Enqueued by BuildAttemptObserver.


Getting Started
---------------

    # run a worker
    QUEUE=ci rake resque:work


Prerequisites
--------------
The worker machines need to have:
Ruby 2.0
rvm
git (we recommend the same version of git that your git server is running)