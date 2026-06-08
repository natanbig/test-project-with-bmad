package producer

import (
	"bytes"
	"compress/gzip"
	"io"
	"testing"

	"github.com/klauspost/compress/zstd"
)

func TestCompressPayload_GzipMetadataAndRoundTrip(t *testing.T) {
	raw := bytes.Repeat([]byte("abc"), 128)
	compressed, compression, err := CompressPayload("gzip", raw)
	if err != nil {
		t.Fatalf("CompressPayload(gzip) error: %v", err)
	}
	if compression != "COMPRESSION_GZIP" {
		t.Fatalf("unexpected compression metadata: got %s", compression)
	}

	zr, err := gzip.NewReader(bytes.NewReader(compressed))
	if err != nil {
		t.Fatalf("gzip reader: %v", err)
	}
	decompressed, err := io.ReadAll(zr)
	if err != nil {
		t.Fatalf("gzip read all: %v", err)
	}
	if err := zr.Close(); err != nil {
		t.Fatalf("gzip close: %v", err)
	}
	if !bytes.Equal(raw, decompressed) {
		t.Fatalf("gzip round-trip mismatch")
	}
}

func TestCompressPayload_ZstdMetadataAndRoundTrip(t *testing.T) {
	raw := bytes.Repeat([]byte("xyz"), 128)
	compressed, compression, err := CompressPayload("zstd", raw)
	if err != nil {
		t.Fatalf("CompressPayload(zstd) error: %v", err)
	}
	if compression != "COMPRESSION_ZSTD" {
		t.Fatalf("unexpected compression metadata: got %s", compression)
	}

	dec, err := zstd.NewReader(nil)
	if err != nil {
		t.Fatalf("zstd reader: %v", err)
	}
	decompressed, err := dec.DecodeAll(compressed, nil)
	if err != nil {
		t.Fatalf("zstd decode: %v", err)
	}
	dec.Close()

	if !bytes.Equal(raw, decompressed) {
		t.Fatalf("zstd round-trip mismatch")
	}
}

func TestCompressPayload_UnsupportedCompression(t *testing.T) {
	if _, _, err := CompressPayload("brotli", []byte("abc")); err == nil {
		t.Fatalf("expected unsupported compression error")
	}
}
