package cfg

import (
	"os"
	"path/filepath"
	"testing"
)

func setupTestConfig(t *testing.T, envFiles, secretFiles map[string]string) string {
	t.Helper()
	base := t.TempDir()

	envDir := filepath.Join(base, "config", "env")
	secretDir := filepath.Join(base, "config", "secret")

	if err := os.MkdirAll(envDir, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.MkdirAll(secretDir, 0o755); err != nil {
		t.Fatal(err)
	}

	for k, v := range envFiles {
		if err := os.WriteFile(filepath.Join(envDir, k), []byte(v), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	for k, v := range secretFiles {
		if err := os.WriteFile(filepath.Join(secretDir, k), []byte(v), 0o644); err != nil {
			t.Fatal(err)
		}
	}

	return base
}

func TestLoad(t *testing.T) {
	base := setupTestConfig(t,
		map[string]string{
			"LOG_LEVEL": "debug",
			"PORT":      "9090",
		},
		map[string]string{
			"API_KEY": "secret123",
		},
	)

	cfg, err := Load(base)
	if err != nil {
		t.Fatalf("Load() error: %v", err)
	}

	if got := cfg.Env().Get("LOG_LEVEL"); got != "debug" {
		t.Errorf("Env().Get(LOG_LEVEL) = %q, want %q", got, "debug")
	}

	if got := cfg.Secret().Get("API_KEY"); got != "secret123" {
		t.Errorf("Secret().Get(API_KEY) = %q, want %q", got, "secret123")
	}

	if got, err := cfg.Env().GetInt("PORT"); err != nil || got != 9090 {
		t.Errorf("Env().GetInt(PORT) = %d, %v; want 9090, nil", got, err)
	}
}

func TestEnvOverride(t *testing.T) {
	base := setupTestConfig(t,
		map[string]string{"LOG_LEVEL": "info"},
		nil,
	)

	t.Setenv("LOG_LEVEL", "error")

	cfg, err := Load(base)
	if err != nil {
		t.Fatalf("Load() error: %v", err)
	}

	if got := cfg.Env().Get("LOG_LEVEL"); got != "error" {
		t.Errorf("env override: got %q, want %q", got, "error")
	}
}

func TestGetOrDefault(t *testing.T) {
	base := setupTestConfig(t, nil, nil)

	cfg, err := Load(base)
	if err != nil {
		t.Fatalf("Load() error: %v", err)
	}

	if got := cfg.Env().GetOrDefault("MISSING", "fallback"); got != "fallback" {
		t.Errorf("GetOrDefault(MISSING) = %q, want %q", got, "fallback")
	}

	if got := cfg.Env().GetIntOrDefault("MISSING", 42); got != 42 {
		t.Errorf("GetIntOrDefault(MISSING) = %d, want 42", got)
	}

	if got := cfg.Env().GetBoolOrDefault("MISSING", true); !got {
		t.Error("GetBoolOrDefault(MISSING) = false, want true")
	}
}

func TestMissingDirs(t *testing.T) {
	base := t.TempDir() // no config/ dirs at all

	cfg, err := Load(base)
	if err != nil {
		t.Fatalf("Load() should not error on missing dirs: %v", err)
	}

	if got := cfg.Env().Get("ANYTHING"); got != "" {
		t.Errorf("expected empty, got %q", got)
	}
}

func TestTrimWhitespace(t *testing.T) {
	base := setupTestConfig(t,
		map[string]string{"HOST": "  localhost\n"},
		nil,
	)

	cfg, err := Load(base)
	if err != nil {
		t.Fatal(err)
	}

	if got := cfg.Env().Get("HOST"); got != "localhost" {
		t.Errorf("Get(HOST) = %q, want %q (trimmed)", got, "localhost")
	}
}

func TestKeys(t *testing.T) {
	base := setupTestConfig(t,
		map[string]string{"A": "1", "B": "2", "C": "3"},
		nil,
	)

	cfg, err := Load(base)
	if err != nil {
		t.Fatal(err)
	}

	keys := cfg.Env().Keys()
	if len(keys) != 3 {
		t.Errorf("Keys() returned %d keys, want 3", len(keys))
	}
}
