package producer

import (
	"bytes"
	"compress/gzip"
	"fmt"
	"strings"

	"github.com/ejh/test-project-with-bmad/pkg/contract"
	"github.com/klauspost/compress/zstd"
)

// CompressPayload compresses raw payload bytes with the selected algorithm and returns contract metadata.
func CompressPayload(algorithm string, raw []byte) ([]byte, string, error) {
	switch strings.ToLower(algorithm) {
	case "gzip":
		var out bytes.Buffer
		zw := gzip.NewWriter(&out)
		if _, err := zw.Write(raw); err != nil {
			return nil, "", fmt.Errorf("gzip compress: %w", err)
		}
		if err := zw.Close(); err != nil {
			return nil, "", fmt.Errorf("gzip close: %w", err)
		}
		return out.Bytes(), contract.CompressionGzip, nil
	case "zstd":
		enc, err := zstd.NewWriter(nil)
		if err != nil {
			return nil, "", fmt.Errorf("zstd writer: %w", err)
		}
		defer enc.Close()
		compressed := enc.EncodeAll(raw, nil)
		return compressed, contract.CompressionZstd, nil
	default:
		return nil, "", fmt.Errorf("unsupported compression %q", algorithm)
	}
}
