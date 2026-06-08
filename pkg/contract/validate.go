package contract

import "fmt"

// Compression values mirror proto enum names for validation without requiring generated code.
const (
	CompressionUnspecified = "COMPRESSION_UNSPECIFIED"
	CompressionGzip        = "COMPRESSION_GZIP"
	CompressionZstd        = "COMPRESSION_ZSTD"
)

// Envelope is a minimal contract view used by validation logic and tests.
type Envelope struct {
	MessageID           string
	ProducerID          string
	CreatedAtUnixMS     int64
	Compression         string
	OriginalSizeBytes   uint64
	CompressedSizeBytes uint64
	Payload             []byte
}

// ValidateEnvelope checks required contract fields and size bounds.
func ValidateEnvelope(e Envelope, payloadMinBytes, payloadMaxBytes uint64) error {
	if payloadMinBytes > payloadMaxBytes {
		return fmt.Errorf("invalid bounds: payload_min_bytes (%d) is greater than payload_max_bytes (%d)", payloadMinBytes, payloadMaxBytes)
	}

	if e.MessageID == "" {
		return fmt.Errorf("message_id is required")
	}
	if e.ProducerID == "" {
		return fmt.Errorf("producer_id is required")
	}
	if e.CreatedAtUnixMS <= 0 {
		return fmt.Errorf("created_at_unix_ms must be a positive unix timestamp in milliseconds")
	}

	switch e.Compression {
	case CompressionGzip, CompressionZstd:
		// valid
	default:
		return fmt.Errorf("unsupported compression: %q", e.Compression)
	}

	if e.OriginalSizeBytes < payloadMinBytes || e.OriginalSizeBytes > payloadMaxBytes {
		return fmt.Errorf("original_size_bytes (%d) out of bounds: expected %d <= original_size_bytes <= %d", e.OriginalSizeBytes, payloadMinBytes, payloadMaxBytes)
	}

	if e.CompressedSizeBytes == 0 {
		return fmt.Errorf("compressed_size_bytes must be greater than zero")
	}
	if len(e.Payload) == 0 {
		return fmt.Errorf("payload must not be empty")
	}

	return nil
}
