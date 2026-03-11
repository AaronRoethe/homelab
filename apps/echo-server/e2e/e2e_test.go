//go:build e2e

package e2e

import (
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"sync"
	"testing"
	"time"
)

var serviceURL string

func TestMain(m *testing.M) {
	serviceURL = os.Getenv("SERVICE_URL")
	if serviceURL == "" {
		fmt.Fprintln(os.Stderr, "SERVICE_URL environment variable is required")
		os.Exit(1)
	}
	os.Exit(m.Run())
}

// --- API Contract Tests ---

func TestHealthEndpoint(t *testing.T) {
	resp, err := http.Get(serviceURL + "/healthz")
	if err != nil {
		t.Fatalf("request failed: %v", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != 200 {
		t.Fatalf("expected 200, got %d", resp.StatusCode)
	}

	var body map[string]string
	if err := json.NewDecoder(resp.Body).Decode(&body); err != nil {
		t.Fatalf("failed to decode response: %v", err)
	}

	if body["status"] != "ok" {
		t.Errorf("expected status 'ok', got '%s'", body["status"])
	}
}

func TestReadinessEndpoint(t *testing.T) {
	resp, err := http.Get(serviceURL + "/ready")
	if err != nil {
		t.Fatalf("request failed: %v", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != 200 {
		t.Fatalf("expected 200, got %d", resp.StatusCode)
	}
}

func TestEchoEndpoint(t *testing.T) {
	resp, err := http.Get(serviceURL + "/")
	if err != nil {
		t.Fatalf("request failed: %v", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != 200 {
		t.Fatalf("expected 200, got %d", resp.StatusCode)
	}

	var body map[string]any
	if err := json.NewDecoder(resp.Body).Decode(&body); err != nil {
		t.Fatalf("failed to decode response: %v", err)
	}

	requiredFields := []string{"hostname", "timestamp", "method", "path", "headers", "go", "arch"}
	for _, field := range requiredFields {
		if _, ok := body[field]; !ok {
			t.Errorf("missing required field: %s", field)
		}
	}
}

func TestContentTypeIsJSON(t *testing.T) {
	resp, err := http.Get(serviceURL + "/")
	if err != nil {
		t.Fatalf("request failed: %v", err)
	}
	defer resp.Body.Close()

	ct := resp.Header.Get("Content-Type")
	if ct != "application/json" {
		t.Errorf("expected Content-Type application/json, got %s", ct)
	}
}

// --- Behavioral Tests ---

func TestEchoReturnsRequestHeaders(t *testing.T) {
	req, _ := http.NewRequest("GET", serviceURL+"/", nil)
	req.Header.Set("X-Test-Header", "e2e-test-value")

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatalf("request failed: %v", err)
	}
	defer resp.Body.Close()

	var body map[string]any
	json.NewDecoder(resp.Body).Decode(&body)

	headers, ok := body["headers"].(map[string]any)
	if !ok {
		t.Fatal("headers field is not a map")
	}

	vals, ok := headers["X-Test-Header"].([]any)
	if !ok || len(vals) == 0 {
		t.Error("expected X-Test-Header to be forwarded in response")
		return
	}

	if vals[0] != "e2e-test-value" {
		t.Errorf("expected header value 'e2e-test-value', got '%v'", vals[0])
	}
}

func TestEchoReturnsCorrectMethod(t *testing.T) {
	resp, err := http.Get(serviceURL + "/")
	if err != nil {
		t.Fatalf("request failed: %v", err)
	}
	defer resp.Body.Close()

	var body map[string]any
	json.NewDecoder(resp.Body).Decode(&body)

	if body["method"] != "GET" {
		t.Errorf("expected method GET, got %v", body["method"])
	}
}

// --- Load Tests ---

func TestConcurrentRequests(t *testing.T) {
	const numRequests = 50
	var wg sync.WaitGroup
	errors := make(chan error, numRequests)

	for range numRequests {
		wg.Add(1)
		go func() {
			defer wg.Done()
			resp, err := http.Get(serviceURL + "/healthz")
			if err != nil {
				errors <- fmt.Errorf("request failed: %w", err)
				return
			}
			defer resp.Body.Close()
			if resp.StatusCode != 200 {
				errors <- fmt.Errorf("expected 200, got %d", resp.StatusCode)
			}
		}()
	}

	wg.Wait()
	close(errors)

	var errs []error
	for err := range errors {
		errs = append(errs, err)
	}

	if len(errs) > 0 {
		t.Errorf("%d/%d requests failed:", len(errs), numRequests)
		for _, err := range errs {
			t.Errorf("  %v", err)
		}
	}
}

func TestResponseLatency(t *testing.T) {
	const maxLatency = 500 * time.Millisecond
	const numRequests = 10

	var latencies []time.Duration

	for i := range numRequests {
		start := time.Now()
		resp, err := http.Get(serviceURL + "/healthz")
		elapsed := time.Since(start)
		if err != nil {
			t.Fatalf("request %d failed: %v", i, err)
		}
		resp.Body.Close()
		latencies = append(latencies, elapsed)
	}

	// Check p99 (with 10 requests, this is effectively the max)
	var maxObserved time.Duration
	for _, l := range latencies {
		if l > maxObserved {
			maxObserved = l
		}
	}

	if maxObserved > maxLatency {
		t.Errorf("p99 latency %v exceeds threshold %v", maxObserved, maxLatency)
	}

	t.Logf("latency stats: max=%v (threshold=%v)", maxObserved, maxLatency)
}
