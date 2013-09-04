Kochiku Worker
==============

Kochiku-worker is the builder component of [Kochiku](https://github.com/square/kochiku). The worker code is deployed to each computer that will be running Build Attempt jobs that are enqueued by BuildPartitioningJobs from Kochiku.

Since Kochiku uses [Resque](https://github.com/resque/resque) jobs, a kochiku-worker is essentially just a Resque worker. All of the techniques that you can use with Resque workers, like the environment variables and unix signals, will also work on Kochiku workers.

### Running in development

Follow the [Running Kochiku in development](https://github.com/square/kochiku/wiki/Hacking-on-Kochiku#running-kochiku-in-development) instructions on the Hacking on Kochiku wiki page.

### Deployment

Instructions are on the [Installation & Deployment](https://github.com/square/kochiku/wiki/Installation-&-Deployment#installing-workers) page on the Kochiku wiki.

