// echo-server is a lightweight HTTP service that echoes request metadata as JSON.
//
//	@title			echo-server API
//	@version		0.1.0
//	@description	A simple HTTP echo service for homelab. Returns request metadata, health status, and readiness.
//
//	@host		localhost:8080
//	@BasePath	/
package main

import (
	"context"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"strings"
	"syscall"
	"time"

	"github.com/AaronRoethe/homelab/apps/echo-server/internal/handler"

	_ "github.com/AaronRoethe/homelab/apps/echo-server/docs"
	httpSwagger "github.com/swaggo/http-swagger/v2"
)

func main() {
	level := parseLogLevel(os.Getenv("LOG_LEVEL"))
	logger := slog.New(slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{
		Level: level,
	}))
	slog.SetDefault(logger)

	mux := http.NewServeMux()
	mux.HandleFunc("GET /", handler.HandleEcho)
	mux.HandleFunc("GET /healthz", handler.HandleHealth)
	mux.HandleFunc("GET /ready", handler.HandleHealth)
	mux.Handle("GET /swagger/", httpSwagger.Handler(
		httpSwagger.URL("/swagger/doc.json"),
	))

	srv := &http.Server{
		Addr:         ":8080",
		Handler:      withLogging(mux),
		ReadTimeout:  5 * time.Second,
		WriteTimeout: 10 * time.Second,
		IdleTimeout:  60 * time.Second,
	}

	go func() {
		slog.Info("starting server", "addr", srv.Addr, "log_level", level.String())
		if err := srv.ListenAndServe(); err != http.ErrServerClosed {
			slog.Error("server error", "err", err)
			os.Exit(1)
		}
	}()

	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGTERM, syscall.SIGINT)
	sig := <-quit
	slog.Info("shutting down", "signal", sig.String())

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	if err := srv.Shutdown(ctx); err != nil {
		slog.Error("shutdown error", "err", err)
	}
}

func parseLogLevel(s string) slog.Level {
	switch strings.ToLower(strings.TrimSpace(s)) {
	case "debug":
		return slog.LevelDebug
	case "warn", "warning":
		return slog.LevelWarn
	case "error":
		return slog.LevelError
	default:
		return slog.LevelInfo
	}
}

type statusRecorder struct {
	http.ResponseWriter
	status int
}

func (r *statusRecorder) WriteHeader(code int) {
	r.status = code
	r.ResponseWriter.WriteHeader(code)
}

func withLogging(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		rec := &statusRecorder{ResponseWriter: w, status: http.StatusOK}

		next.ServeHTTP(rec, r)

		elapsed := time.Since(start)

		// Health/ready/swagger log at debug to reduce noise
		if r.URL.Path == "/healthz" || r.URL.Path == "/ready" || strings.HasPrefix(r.URL.Path, "/swagger/") {
			slog.Debug("request",
				"method", r.Method,
				"path", r.URL.Path,
				"status", rec.status,
				"duration_ms", elapsed.Milliseconds(),
				"remote", r.RemoteAddr,
			)
			return
		}

		slog.Info("request",
			"method", r.Method,
			"path", r.URL.Path,
			"status", rec.status,
			"duration_ms", elapsed.Milliseconds(),
			"remote", r.RemoteAddr,
			"user_agent", r.UserAgent(),
		)
	})
}
