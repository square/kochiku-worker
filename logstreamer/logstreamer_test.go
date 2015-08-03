package main

import (
	"encoding/json"
	"fmt"
	"io/ioutil"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/julienschmidt/httprouter"
	"github.com/stretchr/testify/assert"
)

func TestStatus(t *testing.T) {
	req, err := http.NewRequest("GET", "http://localhost:8080/_status", nil)
	if err != nil {
		t.FailNow()
	}

	w := httptest.NewRecorder()
	status(w, req, nil)

	fmt.Println(w.Code)
	assert.Equal(t, 200, w.Code, "")
}

func outputLogHelper(t *testing.T, id string, logName string, querystring string) *httptest.ResponseRecorder {
	request_url := "http://localhost:8080/build_attempts/" + id + "/log/" + logName + "?" + querystring

	var ps httprouter.Params
	ps = make([]httprouter.Param, 2)
	idParam := httprouter.Param{Key: "id", Value: id}
	logNameParam := httprouter.Param{Key: "logName", Value: logName}

	ps[0] = idParam
	ps[1] = logNameParam

	req, err := http.NewRequest("GET", request_url, nil)
	if err != nil {
		t.FailNow()
	}

	w := httptest.NewRecorder()
	outputLog(w, req, ps)
	return w
}

func outputLogHelperJson(t *testing.T, id string, logName string, querystring string) (int, logResponse) {
	w := outputLogHelper(t, id, logName, querystring)

	body, err := ioutil.ReadAll(w.Body)
	if err != nil {
		t.FailNow()
	}

	var resp logResponse
	err = json.Unmarshal(body, &resp)
	if err != nil {
		t.FailNow()
	}

	return w.Code, resp
}

func TestOutputLogDoesNotExist(t *testing.T) {
	w := outputLogHelper(t, "999", "stdout.log", "")
	assert.Equal(t, 404, w.Code, "Returns 404 for log that does not exist")
}

func TestOutputLogDoesExist(t *testing.T) {
	w := outputLogHelper(t, "100", "stdout.log", "")
	assert.Equal(t, 200, w.Code, "Returns 200 for log that exists")
}

func TestOutputLogInvalidInput(t *testing.T) {
	w := outputLogHelper(t, "a", "stdout.log", "")
	assert.Equal(t, 422, w.Code, "Returns 422 for invalid build attempt name.")

	w = outputLogHelper(t, "a", "not_stdout", "")
	assert.Equal(t, 422, w.Code, "Returns 422 for invalid log name")
}

func TestOutputLogEntireLog(t *testing.T) {
	respCode, resp := outputLogHelperJson(t, "100", "stdout.log", "")
	assert.Equal(t, 200, respCode, "")
	assert.Equal(t, 0, resp.Start, "")
	assert.Equal(t, 27, resp.BytesRead, "")
	assert.Equal(t, "Hello\nline 2\nline 3\nline 4\n", resp.Contents, "")
}

func TestOutputLogPartialLogHead(t *testing.T) {
	respCode, resp := outputLogHelperJson(t, "100", "stdout.log", "maxBytes=13")
	assert.Equal(t, 200, respCode, "")
	assert.Equal(t, 0, resp.Start, "")
	assert.Equal(t, 13, resp.BytesRead, "")
	assert.Equal(t, "Hello\nline 2\n", resp.Contents, "")
}

func TestOutputLogPartialLogTail(t *testing.T) {
	respCode, resp := outputLogHelperJson(t, "100", "stdout.log", "start=1")
	assert.Equal(t, 200, respCode, "")
	assert.Equal(t, 1, resp.Start, "")
	assert.Equal(t, 26, resp.BytesRead, "")
	assert.Equal(t, "ello\nline 2\nline 3\nline 4\n", resp.Contents, "")
}

func TestOutputLogNotEnoughBytes(t *testing.T) {
	respCode, resp := outputLogHelperJson(t, "100", "stdout.log", "start=6&maxBytes=5")
	assert.Equal(t, 200, respCode, "")
	assert.Equal(t, 6, resp.Start, "")
	assert.Equal(t, 0, resp.BytesRead, "")
	assert.Equal(t, "", resp.Contents, "")
}

func TestOutputLogEmpty(t *testing.T) {
	respCode, resp := outputLogHelperJson(t, "100", "stdout.log", "maxBytes=0")
	assert.Equal(t, 200, respCode, "")
	assert.Equal(t, 0, resp.Start, "")
	assert.Equal(t, 0, resp.BytesRead, "")
	assert.Equal(t, "", resp.Contents, "")
}

func TestOutputLogInvalidStart(t *testing.T) {
	respCode, resp := outputLogHelperJson(t, "100", "stdout.log", "start=junk")
	assert.Equal(t, 200, respCode, "")
	assert.Equal(t, 0, resp.Start, "start should default to 0 on error")
}

func TestOutputLogInvalidNumLines(t *testing.T) {
	respCode, resp := outputLogHelperJson(t, "100", "stdout.log", "maxBytes=junk")
	assert.Equal(t, 200, respCode, "")
	assert.Equal(t, 27, resp.BytesRead, "should return entire log on invalid numLines")
}

func TestOutputLogTail(t *testing.T) {
	respCode, resp := outputLogHelperJson(t, "100", "stdout.log", "start=-1&maxBytes=8")
	assert.Equal(t, 200, respCode, "")
	assert.Equal(t, 7, resp.BytesRead, "should return last line")
	assert.Equal(t, "line 4\n", resp.Contents, "")
}
