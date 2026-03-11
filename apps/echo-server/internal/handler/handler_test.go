package handler

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"runtime"
	"testing"
)

func TestHandleHealth(t *testing.T) {
	req := httptest.NewRequest(http.MethodGet, "/healthz", nil)
	w := httptest.NewRecorder()

	HandleHealth(w, req)

	if w.Code != http.StatusOK {
		t.Errorf("expected status 200, got %d", w.Code)
	}

	if ct := w.Header().Get("Content-Type"); ct != "application/json" {
		t.Errorf("expected Content-Type application/json, got %s", ct)
	}

	var resp HealthResponse
	if err := json.Unmarshal(w.Body.Bytes(), &resp); err != nil {
		t.Fatalf("failed to unmarshal response: %v", err)
	}

	if resp.Status != "ok" {
		t.Errorf("expected status 'ok', got '%s'", resp.Status)
	}
}

func TestHandleEcho(t *testing.T) {
	req := httptest.NewRequest(http.MethodGet, "/", nil)
	req.Header.Set("X-Test-Header", "hello")
	w := httptest.NewRecorder()

	HandleEcho(w, req)

	if w.Code != http.StatusOK {
		t.Errorf("expected status 200, got %d", w.Code)
	}

	if ct := w.Header().Get("Content-Type"); ct != "application/json" {
		t.Errorf("expected Content-Type application/json, got %s", ct)
	}

	var resp EchoResponse
	if err := json.Unmarshal(w.Body.Bytes(), &resp); err != nil {
		t.Fatalf("failed to unmarshal response: %v", err)
	}

	if resp.Hostname == "" {
		t.Error("expected hostname to be set")
	}
	if resp.Timestamp == "" {
		t.Error("expected timestamp to be set")
	}
	if resp.Method != "GET" {
		t.Errorf("expected method GET, got %s", resp.Method)
	}
	if resp.Path != "/" {
		t.Errorf("expected path /, got %s", resp.Path)
	}
	if resp.Arch != runtime.GOARCH {
		t.Errorf("expected arch %s, got %s", runtime.GOARCH, resp.Arch)
	}
	if resp.Headers.Get("X-Test-Header") != "hello" {
		t.Error("expected X-Test-Header to be forwarded")
	}
}

func TestHandleEchoReturnsRequestPath(t *testing.T) {
	req := httptest.NewRequest(http.MethodGet, "/some/path", nil)
	w := httptest.NewRecorder()

	HandleEcho(w, req)

	var resp EchoResponse
	json.Unmarshal(w.Body.Bytes(), &resp)

	if resp.Path != "/some/path" {
		t.Errorf("expected path /some/path, got %s", resp.Path)
	}
}
