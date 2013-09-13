Kochiku Worker
==============

Kochiku-worker is the builder component of [Kochiku](https://github.com/square/kochiku). The worker code is deployed to each computer that runs [`BuildAttemptJob`s](https://github.com/square/kochiku-worker/blob/master/spec/jobs/build_attempt_job_spec.rb), which are enqueued by [`BuildPartitioningJob`s](https://github.com/square/kochiku/blob/master/spec/jobs/build_partitioning_job_spec.rb) from Kochiku.

Since Kochiku uses [Resque](https://github.com/resque/resque) jobs, a kochiku-worker is essentially just a Resque worker. All of the techniques that you can use with Resque workers, such as the environment variables and Unix signals, also work with Kochiku workers.

### Running in development

See the [Running Kochiku in development](https://github.com/square/kochiku/wiki/Hacking-on-Kochiku#running-kochiku-in-development) section of the Hacking on Kochiku wiki page.

### Deployment

See the [Installation & Deployment](https://github.com/square/kochiku/wiki/Installation-&-Deployment#installing-workers) page of the Kochiku wiki.

