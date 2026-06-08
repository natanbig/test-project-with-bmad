package contract

import "testing"

func TestValidateEnvelope_ValidBoundaries(t *testing.T) {
	const (
		payloadMin = uint64(128)
		payloadMax = uint64(4096)
	)

	base := Envelope{
		MessageID:           "msg-1",
		ProducerID:          "producer-a",
		CreatedAtUnixMS:     1,
		Compression:         CompressionGzip,
		CompressedSizeBytes: 64,
		Payload:             []byte{1, 2, 3},
	}

	minCase := base
	minCase.OriginalSizeBytes = payloadMin
	if err := ValidateEnvelope(minCase, payloadMin, payloadMax); err != nil {
		t.Fatalf("expected min boundary to be valid, got error: %v", err)
	}

	maxCase := base
	maxCase.Compression = CompressionZstd
	maxCase.OriginalSizeBytes = payloadMax
	if err := ValidateEnvelope(maxCase, payloadMin, payloadMax); err != nil {
		t.Fatalf("expected max boundary to be valid, got error: %v", err)
	}
}

func TestValidateEnvelope_InvalidBounds(t *testing.T) {
	const (
		payloadMin = uint64(100)
		payloadMax = uint64(1000)
	)

	base := Envelope{
		MessageID:           "msg-2",
		ProducerID:          "producer-b",
		CreatedAtUnixMS:     1700000000000,
		Compression:         CompressionGzip,
		CompressedSizeBytes: 80,
		Payload:             []byte{9, 9, 9},
	}

	belowMin := base
	belowMin.OriginalSizeBytes = payloadMin - 1
	if err := ValidateEnvelope(belowMin, payloadMin, payloadMax); err == nil {
		t.Fatalf("expected error for original_size_bytes below payload_min_bytes")
	}

	aboveMax := base
	aboveMax.OriginalSizeBytes = payloadMax + 1
	if err := ValidateEnvelope(aboveMax, payloadMin, payloadMax); err == nil {
		t.Fatalf("expected error for original_size_bytes above payload_max_bytes")
	}
}

func TestValidateEnvelope_InvalidEnvelopeFields(t *testing.T) {
	e := Envelope{
		MessageID:           "msg-3",
		ProducerID:          "producer-c",
		CreatedAtUnixMS:     1700000000000,
		Compression:         CompressionUnspecified,
		OriginalSizeBytes:   256,
		CompressedSizeBytes: 200,
		Payload:             []byte{1},
	}

	if err := ValidateEnvelope(e, 1, 1000); err == nil {
		t.Fatalf("expected unsupported compression error")
	}
}
