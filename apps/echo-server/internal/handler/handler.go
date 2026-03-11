package handler

import (
	"encoding/json"
	"net/http"
	"os"
	"runtime"
	"time"
)

// EchoResponse is the JSON structure returned by the echo endpoint.
type EchoResponse struct {
	Hostname  string      `json:"hostname"`
	Timestamp string      `json:"timestamp"`
	Method    string      `json:"method"`
	Path      string      `json:"path"`
	Headers   http.Header `json:"headers"`
	Go        string      `json:"go"`
	Arch      string      `json:"arch"`
}

// HealthResponse is the JSON structure returned by health endpoints.
type HealthResponse struct {
	Status string `json:"status"`
}

// HandleEcho returns request metadata as JSON.
func HandleEcho(w http.ResponseWriter, r *http.Request) {
	hostname, _ := os.Hostname()

	resp := EchoResponse{
		Hostname:  hostname,
		Timestamp: time.Now().UTC().Format(time.RFC3339),
		Method:    r.Method,
		Path:      r.URL.Path,
		Headers:   r.Header,
		Go:        runtime.Version(),
		Arch:      runtime.GOARCH,
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(resp)
}

// HandleHealth returns a simple health status.
func HandleHealth(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(HealthResponse{Status: "ok"})
}
