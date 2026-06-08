package consumer

import (
	"fmt"
	"os"
	"strconv"
)

const (
	defaultOTLPListenAddr    = ":4317"
	defaultMetricsListenAddr = ":2113"
	defaultPayloadMinBytes   = 128
	defaultPayloadMaxBytes   = 4096
)

// Config controls consumer behavior.
type Config struct {
	OTLPListenAddr    string
	MetricsListenAddr string
	PayloadMinBytes   uint64
	PayloadMaxBytes   uint64
}

// LoadConfig loads consumer config from env with defaults.
func LoadConfig() (Config, error) {
	cfg := Config{
		OTLPListenAddr:    envString("CONSUMER_OTLP_LISTEN_ADDR", defaultOTLPListenAddr),
		MetricsListenAddr: envString("CONSUMER_METRICS_LISTEN_ADDR", defaultMetricsListenAddr),
		PayloadMinBytes:   envUint64("PAYLOAD_MIN_BYTES", defaultPayloadMinBytes),
		PayloadMaxBytes:   envUint64("PAYLOAD_MAX_BYTES", defaultPayloadMaxBytes),
	}

	if cfg.PayloadMinBytes > cfg.PayloadMaxBytes {
		return Config{}, fmt.Errorf("invalid payload bounds: min (%d) > max (%d)", cfg.PayloadMinBytes, cfg.PayloadMaxBytes)
	}

	return cfg, nil
}

func envString(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
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
