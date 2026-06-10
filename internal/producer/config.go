package producer

import (
	"fmt"
	"os"
	"strconv"
	"strings"
	"time"
)

const (
	defaultProducerID                 = "producer-1"
	defaultPayloadMinBytes     uint64 = 128
	defaultPayloadMaxBytes     uint64 = 4096
	defaultCompression                = "gzip"
	defaultOTLPEndpoint               = "localhost:4317"
	defaultInsecure                   = true
	defaultSendInterval               = 2000 * time.Millisecond
	defaultMetricsListenAddr          = ":2112"
	defaultRetryMaxAttempts           = 5
	defaultRetryInitialBackoff        = 100 * time.Millisecond
	defaultRetryMaxBackoff            = 2 * time.Second
	defaultRetryTimeout               = 5 * time.Second
)

// Config controls producer behavior.
type Config struct {
	ProducerID        string
	PayloadMinBytes   uint64
	PayloadMaxBytes   uint64
	Compression       string
	OTLPEndpoint      string
	OTLPInsecure      bool
	SendInterval      time.Duration
	MetricsListenAddr string
	Retry             RetryConfig
}

// LoadConfig loads producer config from env with defaults.
func LoadConfig() (Config, error) {
	cfg := Config{
		ProducerID:        envString("PRODUCER_ID", defaultProducerID),
		PayloadMinBytes:   envUint64("PAYLOAD_MIN_BYTES", defaultPayloadMinBytes),
		PayloadMaxBytes:   envUint64("PAYLOAD_MAX_BYTES", defaultPayloadMaxBytes),
		Compression:       strings.ToLower(envString("COMPRESSION", defaultCompression)),
		OTLPEndpoint:      envString("OTLP_ENDPOINT", defaultOTLPEndpoint),
		OTLPInsecure:      envBool("OTLP_INSECURE", defaultInsecure),
		SendInterval:      envDurationMS("SEND_INTERVAL_MS", defaultSendInterval),
		MetricsListenAddr: envString("METRICS_LISTEN_ADDR", defaultMetricsListenAddr),
		Retry: RetryConfig{
			MaxAttempts:    envInt("RETRY_MAX_ATTEMPTS", defaultRetryMaxAttempts),
			InitialBackoff: envDurationMS("RETRY_INITIAL_BACKOFF_MS", defaultRetryInitialBackoff),
			MaxBackoff:     envDurationMS("RETRY_MAX_BACKOFF_MS", defaultRetryMaxBackoff),
			Timeout:        envDurationMS("RETRY_TIMEOUT_MS", defaultRetryTimeout),
		},
	}

	if cfg.PayloadMinBytes > cfg.PayloadMaxBytes {
		return Config{}, fmt.Errorf("invalid payload bounds: min (%d) > max (%d)", cfg.PayloadMinBytes, cfg.PayloadMaxBytes)
	}
	if cfg.Retry.MaxAttempts < 1 {
		return Config{}, fmt.Errorf("retry max attempts must be >= 1")
	}
	if cfg.Retry.InitialBackoff <= 0 || cfg.Retry.MaxBackoff <= 0 || cfg.Retry.Timeout <= 0 {
		return Config{}, fmt.Errorf("retry durations must be > 0")
	}
	if cfg.Compression != "gzip" && cfg.Compression != "zstd" {
		return Config{}, fmt.Errorf("unsupported COMPRESSION %q; expected gzip or zstd", cfg.Compression)
	}

	return cfg, nil
}

func envString(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}

func envBool(key string, def bool) bool {
	v := os.Getenv(key)
	if v == "" {
		return def
	}
	parsed, err := strconv.ParseBool(v)
	if err != nil {
		return def
	}
	return parsed
}

func envUint64(key string, def uint64) uint64 {
	v := os.Getenv(key)
	if v == "" {
		return def
	}
	parsed, err := strconv.ParseUint(v, 10, 64)
	if err != nil {
		return def
	}
	return parsed
}

func envInt(key string, def int) int {
	v := os.Getenv(key)
	if v == "" {
		return def
	}
	parsed, err := strconv.Atoi(v)
	if err != nil {
		return def
	}
	return parsed
}

func envDurationMS(key string, def time.Duration) time.Duration {
	v := os.Getenv(key)
	if v == "" {
		return def
	}
	ms, err := strconv.ParseInt(v, 10, 64)
	if err != nil || ms <= 0 {
		return def
	}
	return time.Duration(ms) * time.Millisecond
}
