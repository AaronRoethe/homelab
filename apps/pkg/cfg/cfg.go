// Package cfg loads configuration from flat files with environment variable overrides.
//
// It reads from two directories relative to a base path:
//
//	config/env/    — non-secret configuration (one value per file)
//	config/secret/ — sensitive values (one value per file)
//
// Environment variables take precedence over file values. File names match
// environment variable names (e.g., config/env/LOG_LEVEL maps to LOG_LEVEL).
package cfg

import (
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"
)

// Config holds loaded configuration from env and secret directories.
type Config struct {
	env    map[string]string
	secret map[string]string
}

// Load reads config/env and config/secret from the given base path.
// Environment variables override file-based values in the env store.
func Load(basePath string) (*Config, error) {
	c := &Config{
		env:    make(map[string]string),
		secret: make(map[string]string),
	}

	if err := c.loadDir(filepath.Join(basePath, "config", "env"), c.env); err != nil {
		return nil, err
	}
	if err := c.loadDir(filepath.Join(basePath, "config", "secret"), c.secret); err != nil {
		return nil, err
	}

	// Environment variables override file-based env values
	for key := range c.env {
		if v, ok := os.LookupEnv(key); ok {
			c.env[key] = v
		}
	}

	return c, nil
}

// LoadEnv loads from the current working directory.
func LoadEnv() (*Config, error) {
	wd, err := os.Getwd()
	if err != nil {
		return nil, err
	}
	return Load(wd)
}

func (c *Config) loadDir(dir string, store map[string]string) error {
	entries, err := os.ReadDir(dir)
	if os.IsNotExist(err) {
		return nil // directory is optional
	}
	if err != nil {
		return err
	}

	for _, e := range entries {
		if e.IsDir() || strings.HasPrefix(e.Name(), ".") {
			continue
		}
		data, err := os.ReadFile(filepath.Join(dir, e.Name()))
		if err != nil {
			return err
		}
		store[e.Name()] = strings.TrimSpace(string(data))
	}
	return nil
}

// Env returns an accessor for non-secret config values.
func (c *Config) Env() Store { return Store{data: c.env} }

// Secret returns an accessor for secret config values.
func (c *Config) Secret() Store { return Store{data: c.secret} }

// Store provides typed access to a set of key-value pairs.
type Store struct {
	data map[string]string
}

// Get returns the value for key, or empty string if not found.
func (s Store) Get(key string) string {
	return s.data[key]
}

// GetOrDefault returns the value for key, or def if not found or empty.
func (s Store) GetOrDefault(key, def string) string {
	if v, ok := s.data[key]; ok && v != "" {
		return v
	}
	// Also check env var directly for keys not in files
	if v, ok := os.LookupEnv(key); ok && v != "" {
		return v
	}
	return def
}

// GetInt parses the value as an integer.
func (s Store) GetInt(key string) (int, error) {
	return strconv.Atoi(s.Get(key))
}

// GetIntOrDefault parses the value as an integer, returning def on failure.
func (s Store) GetIntOrDefault(key string, def int) int {
	v := s.GetOrDefault(key, "")
	if v == "" {
		return def
	}
	if n, err := strconv.Atoi(v); err == nil {
		return n
	}
	return def
}

// GetBool parses the value as a boolean (true/false/1/0/yes/no).
func (s Store) GetBool(key string) (bool, error) {
	return strconv.ParseBool(s.Get(key))
}

// GetBoolOrDefault parses the value as a boolean, returning def on failure.
func (s Store) GetBoolOrDefault(key string, def bool) bool {
	v := s.Get(key)
	if v == "" {
		return def
	}
	if b, err := strconv.ParseBool(v); err == nil {
		return b
	}
	return def
}

// GetDuration parses the value as a time.Duration (e.g., "5s", "100ms").
func (s Store) GetDuration(key string) (time.Duration, error) {
	return time.ParseDuration(s.Get(key))
}

// GetDurationOrDefault parses the value as a duration, returning def on failure.
func (s Store) GetDurationOrDefault(key string, def time.Duration) time.Duration {
	v := s.Get(key)
	if v == "" {
		return def
	}
	if d, err := time.ParseDuration(v); err == nil {
		return d
	}
	return def
}

// Keys returns all keys in the store.
func (s Store) Keys() []string {
	keys := make([]string, 0, len(s.data))
	for k := range s.data {
		keys = append(keys, k)
	}
	return keys
}
