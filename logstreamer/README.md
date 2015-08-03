# Log streamer
This is an optional log streamer component written in go that can be used with kochiku. It will stream your logs in real time as tests are running.
To run, it requires the master kochiku instance to communicate with the worker nodes on an additional port (that you specify).

## instructions to use with kochiku

- upgrade your kochiku master instance to the latest version on github
- follow the build instructions to generate the logstreamer binary
- copy the logstreamer binary onto each kochiku worker. The workers expect this binary to exist in the logstreamer subdirectory (so the binary will be located at $(KOCHIKU_WORKER_ROOT)/logstreamer/logstreamer)
- in your config/kochiku-worker.yml file, add the following line: `logstreaming_port: $(PORT_NUMBER)` (choose any open, accessible port to reach the master) 

## build instructions

You'll need to download the go distribution (https://golang.org/doc/install)

```
export GOPATH=$(pwd)
go get github.com/julienschmidt/httprouter
go get github.com/stretchr/testify/assert
make
```

## test

```
make test
```

