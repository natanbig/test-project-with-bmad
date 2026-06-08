package producer

import (
	"testing"
	"time"
)

func TestGenerator_RespectsPayloadBounds(t *testing.T) {
	cfg := Config{
		ProducerID:      "producer-a",
		PayloadMinBytes: 32,
		PayloadMaxBytes: 128,
		Compression:     "gzip",
	}

	g := NewGenerator(cfg, 42)

	for i := 0; i < 200; i++ {
		e, err := g.Next(time.Unix(1700000000, int64(i)))
		if err != nil {
			t.Fatalf("Next() error: %v", err)
		}
		if e.OriginalSizeBytes < cfg.PayloadMinBytes || e.OriginalSizeBytes > cfg.PayloadMaxBytes {
			t.Fatalf("payload out of bounds: got %d, expected between %d and %d", e.OriginalSizeBytes, cfg.PayloadMinBytes, cfg.PayloadMaxBytes)
		}
		if len(e.Payload) == 0 {
			t.Fatalf("expected compressed payload bytes")
		}
	}
}

func TestGenerator_CompressionMetadata(t *testing.T) {
	cases := []struct {
		name        string
		compression string
		expect      string
	}{
		{name: "gzip", compression: "gzip", expect: "COMPRESSION_GZIP"},
		{name: "zstd", compression: "zstd", expect: "COMPRESSION_ZSTD"},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			cfg := Config{
				ProducerID:      "producer-b",
				PayloadMinBytes: 64,
				PayloadMaxBytes: 64,
				Compression:     tc.compression,
			}

			g := NewGenerator(cfg, 7)
			e, err := g.Next(time.Unix(1700000000, 0))
			if err != nil {
				t.Fatalf("Next() error: %v", err)
			}
			if e.Compression != tc.expect {
				t.Fatalf("unexpected compression metadata: got %q want %q", e.Compression, tc.expect)
			}
		})
	}
}
