all: build

logstreamer: logstreamer.go
	go build
setup:
	./test_setup.sh

build: logstreamer

test: setup build
	go test

clean:
	rm logstreamer
