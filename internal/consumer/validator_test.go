package consumer

import (
	"testing"

	"github.com/ejh/test-project-with-bmad/pkg/contract"
)

func TestValidatorValidate(t *testing.T) {
	t.Parallel()

	v := NewValidator(64, 1024)
	env := contract.Envelope{
		MessageID:           "m-1",
		ProducerID:          "producer-a",
		CreatedAtUnixMS:     1760000000000,
		Compression:         contract.CompressionGzip,
		OriginalSizeBytes:   256,
		CompressedSizeBytes: 120,
		Payload:             []byte("payload"),
	}

	if err := v.Validate(env); err != nil {
		t.Fatalf("expected envelope to be valid: %v", err)
	}
}

func TestValidatorValidateInvalid(t *testing.T) {
	t.Parallel()

	v := NewValidator(64, 1024)
	env := contract.Envelope{
		MessageID:           "m-1",
		ProducerID:          "producer-a",
		CreatedAtUnixMS:     1760000000000,
		Compression:         contract.CompressionUnspecified,
		OriginalSizeBytes:   10,
		CompressedSizeBytes: 0,
		Payload:             nil,
	}

	if err := v.Validate(env); err == nil {
		t.Fatal("expected invalid envelope error")
	}
}
