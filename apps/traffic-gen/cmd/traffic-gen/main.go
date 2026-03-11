package main

import (
	"encoding/json"
	"fmt"
	"log/slog"
	"math/rand"
	"net/http"
	"os"
	"strconv"
	"time"
)

func main() {
	logger := slog.New(slog.NewJSONHandler(os.Stdout, nil))
	slog.SetDefault(logger)

	cfg := loadConfig()

	slog.Info("starting traffic generator",
		"target", cfg.TargetURL,
		"requests", cfg.Requests,
		"concurrency", cfg.Concurrency,
		"delay_ms", cfg.DelayMs,
	)

	results := run(cfg)
	printSummary(results)

	if results.Failures > 0 {
		os.Exit(1)
	}
}

type config struct {
	TargetURL   string
	Requests    int
	Concurrency int
	DelayMs     int
}

type results struct {
	Total     int
	Successes int
	Failures  int
	MinMs     float64
	MaxMs     float64
	AvgMs     float64
}

func loadConfig() config {
	return config{
		TargetURL:   envOrDefault("TARGET_URL", "http://echo-server:80"),
		Requests:    envIntOrDefault("REQUESTS", 100),
		Concurrency: envIntOrDefault("CONCURRENCY", 5),
		DelayMs:     envIntOrDefault("DELAY_MS", 100),
	}
}

var paths = []string{"/", "/healthz", "/ready"}

func run(cfg config) results {
	sem := make(chan struct{}, cfg.Concurrency)
	type result struct {
		ok      bool
		elapsed time.Duration
	}
	ch := make(chan result, cfg.Requests)

	client := &http.Client{Timeout: 10 * time.Second}

	for i := range cfg.Requests {
		sem <- struct{}{}
		go func(i int) {
			defer func() { <-sem }()

			path := paths[rand.Intn(len(paths))]
			url := cfg.TargetURL + path

			start := time.Now()
			resp, err := client.Get(url)
			elapsed := time.Since(start)

			if err != nil {
				slog.Error("request failed", "url", url, "err", err, "request", i)
				ch <- result{ok: false, elapsed: elapsed}
				return
			}
			defer resp.Body.Close()

			if resp.StatusCode != http.StatusOK {
				slog.Warn("unexpected status", "url", url, "status", resp.StatusCode, "request", i)
				ch <- result{ok: false, elapsed: elapsed}
				return
			}

			// Consume body to ensure connection reuse
			var body map[string]any
			json.NewDecoder(resp.Body).Decode(&body)

			slog.Info("request ok", "url", url, "status", resp.StatusCode, "ms", elapsed.Milliseconds(), "request", i)
			ch <- result{ok: true, elapsed: elapsed}
		}(i)

		if cfg.DelayMs > 0 {
			time.Sleep(time.Duration(cfg.DelayMs) * time.Millisecond)
		}
	}

	// Wait for all goroutines
	for range cfg.Concurrency {
		sem <- struct{}{}
	}
	close(ch)

	var r results
	var totalMs float64
	r.MinMs = 999999

	for res := range ch {
		r.Total++
		ms := float64(res.elapsed.Milliseconds())
		totalMs += ms
		if ms < r.MinMs {
			r.MinMs = ms
		}
		if ms > r.MaxMs {
			r.MaxMs = ms
		}
		if res.ok {
			r.Successes++
		} else {
			r.Failures++
		}
	}

	if r.Total > 0 {
		r.AvgMs = totalMs / float64(r.Total)
	}

	return r
}

func printSummary(r results) {
	fmt.Println()
	fmt.Println("=== Traffic Generator Results ===")
	fmt.Printf("Total:     %d\n", r.Total)
	fmt.Printf("Successes: %d\n", r.Successes)
	fmt.Printf("Failures:  %d\n", r.Failures)
	fmt.Printf("Latency:   min=%.0fms avg=%.0fms max=%.0fms\n", r.MinMs, r.AvgMs, r.MaxMs)

	if r.Failures > 0 {
		fmt.Println("STATUS: FAIL")
	} else {
		fmt.Println("STATUS: PASS")
	}
}

func envOrDefault(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}

func envIntOrDefault(key string, def int) int {
	if v := os.Getenv(key); v != "" {
		if n, err := strconv.Atoi(v); err == nil {
			return n
		}
	}
	return def
}
