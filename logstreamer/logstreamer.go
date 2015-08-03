package main

import (
	"bufio"
	"encoding/json"
	"flag"
	"fmt"
	"log"
	"net/http"
	"os"
	"regexp"
	"strconv"

	"github.com/julienschmidt/httprouter"
)

func status(w http.ResponseWriter, r *http.Request, _ httprouter.Params) {
	w.WriteHeader(http.StatusOK)
}

type logResponse struct {
	Start     int
	Contents  string
	BytesRead int
	LogName   string
}

// seek to Start, and then read to the last newline before/at maxBytes
// if Start is -1, then tail from end of log
func outputLog(w http.ResponseWriter, r *http.Request, ps httprouter.Params) {
	// validate that id is a number
	// validate that logName is stdout.log (for now, only whitelisting this log file)
	// in the future, may support streaming of arbitrary log files.
	idString := ps.ByName("id")
	logName := ps.ByName("logName")

	digitRegex := regexp.MustCompile(`^\d+$`)
	validID := digitRegex.MatchString(idString)
	validLogName := (logName == "stdout.log")

	if validID && validLogName {
		start := r.URL.Query().Get("start")
		maxBytes := r.URL.Query().Get("maxBytes")

		startInt, err := strconv.Atoi(start) // defaults to 0 on parse error
		doTail := startInt < 0

		maxBytesInt, err := strconv.Atoi(maxBytes)
		if err != nil || maxBytesInt < 0 {
			maxBytesInt = 50000 // arbitrary default limit
		}

		// check for existence of file; if DNE return 404
		file, err := os.Open("logs/" + idString + "/" + logName)

		if err != nil {
			w.WriteHeader(http.StatusNotFound)
			return
		}

		defer file.Close()

		fi, err := file.Stat()
		if err != nil {
			w.WriteHeader(http.StatusNotFound)
			return
		}

		size := fi.Size() // File size is needed for tailing log

		if doTail {
			startInt = int(size) - maxBytesInt
			if startInt < 0 {
				startInt = 0
				doTail = false
			}
		}

		actualStart, err := file.Seek(int64(startInt), 0)

		reader := bufio.NewReader(file)

		if doTail {
			// read to next newline beginning from offset (we don't return partial lines)
			buf, _ := reader.ReadBytes('\n')
			actualStart += int64(len(buf))
		}

		contents := ""
		byteCounter := 0

		buffer, err := reader.ReadBytes('\n')
		for err == nil {
			if byteCounter+len(buffer) > maxBytesInt {
				break
			}

			byteCounter += len(buffer)
			contents += string(buffer)
			buffer, err = reader.ReadBytes('\n')
		}

		response := logResponse{
			Start:     int(actualStart),
			Contents:  contents,
			BytesRead: byteCounter,
			LogName:   logName,
		}

		jsonResponse, err := json.Marshal(response)

		w.Header().Set("Content-Type", "application/json")
		w.Write(jsonResponse)
		fmt.Fprint(w, "\n")
	} else {
		http.Error(w, "Invalid params", 422)
		return
	}
}

func main() {
	portPtr := flag.Int("p", 8080, "port number")
	flag.Parse()
	port := strconv.Itoa(*portPtr)

	fmt.Println("Listening on port " + port)
	router := httprouter.New()
	router.GET("/_status", status)
	router.GET("/build_attempts/:id/log/:logName", outputLog)
	log.Fatal(http.ListenAndServe(":"+port, router))
}
