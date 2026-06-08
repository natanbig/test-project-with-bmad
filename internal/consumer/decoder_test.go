package consumer

import (
	"strings"
	"testing"

	commonv1 "go.opentelemetry.io/proto/otlp/common/v1"
	tracev1 "go.opentelemetry.io/proto/otlp/trace/v1"
)

func TestDecodeEnvelopeFromSpanValid(t *testing.T) {
	t.Parallel()

	span := &tracev1.Span{
		Attributes: []*commonv1.KeyValue{
			{Key: "okps.message_id", Value: &commonv1.AnyValue{Value: &commonv1.AnyValue_StringValue{StringValue: "m-1"}}},
			{Key: "okps.producer_id", Value: &commonv1.AnyValue{Value: &commonv1.AnyValue_StringValue{StringValue: "producer-a"}}},
			{Key: "okps.created_at_unix_ms", Value: &commonv1.AnyValue{Value: &commonv1.AnyValue_IntValue{IntValue: 1760000000000}}},
			{Key: "okps.compression", Value: &commonv1.AnyValue{Value: &commonv1.AnyValue_StringValue{StringValue: "COMPRESSION_GZIP"}}},
			{Key: "okps.original_size_bytes", Value: &commonv1.AnyValue{Value: &commonv1.AnyValue_IntValue{IntValue: 256}}},
			{Key: "okps.compressed_size_bytes", Value: &commonv1.AnyValue{Value: &commonv1.AnyValue_IntValue{IntValue: 100}}},
			{Key: "okps.payload", Value: &commonv1.AnyValue{Value: &commonv1.AnyValue_BytesValue{BytesValue: []byte("abc")}}},
		},
	}

	env, err := DecodeEnvelopeFromSpan(span)
	if err != nil {
		t.Fatalf("DecodeEnvelopeFromSpan returned error: %v", err)
	}

	if env.MessageID != "m-1" {
		t.Fatalf("unexpected message id: %q", env.MessageID)
	}
	if env.OriginalSizeBytes != 256 {
		t.Fatalf("unexpected original size: %d", env.OriginalSizeBytes)
	}
	if string(env.Payload) != "abc" {
		t.Fatalf("unexpected payload: %q", string(env.Payload))
	}
}

func TestDecodeEnvelopeFromSpanInvalidEnvelope(t *testing.T) {
	t.Parallel()

	span := &tracev1.Span{
		Attributes: []*commonv1.KeyValue{
			{Key: "okps.producer_id", Value: &commonv1.AnyValue{Value: &commonv1.AnyValue_StringValue{StringValue: "producer-a"}}},
		},
	}

	_, err := DecodeEnvelopeFromSpan(span)
	if err == nil {
		t.Fatal("expected error for invalid envelope")
	}
	if !strings.Contains(err.Error(), "okps.message_id") {
		t.Fatalf("expected missing message_id error, got: %v", err)
	}
}

func TestDecodeEnvelopeFromSpanUnsupportedCompression(t *testing.T) {
	t.Parallel()

	span := &tracev1.Span{
		Attributes: []*commonv1.KeyValue{
			{Key: "okps.message_id", Value: &commonv1.AnyValue{Value: &commonv1.AnyValue_StringValue{StringValue: "m-1"}}},
			{Key: "okps.producer_id", Value: &commonv1.AnyValue{Value: &commonv1.AnyValue_StringValue{StringValue: "producer-a"}}},
			{Key: "okps.created_at_unix_ms", Value: &commonv1.AnyValue{Value: &commonv1.AnyValue_IntValue{IntValue: 1760000000000}}},
			{Key: "okps.compression", Value: &commonv1.AnyValue{Value: &commonv1.AnyValue_StringValue{StringValue: "brotli"}}},
			{Key: "okps.original_size_bytes", Value: &commonv1.AnyValue{Value: &commonv1.AnyValue_IntValue{IntValue: 256}}},
			{Key: "okps.compressed_size_bytes", Value: &commonv1.AnyValue{Value: &commonv1.AnyValue_IntValue{IntValue: 100}}},
			{Key: "okps.payload", Value: &commonv1.AnyValue{Value: &commonv1.AnyValue_BytesValue{BytesValue: []byte("abc")}}},
		},
	}

	_, err := DecodeEnvelopeFromSpan(span)
	if err == nil {
		t.Fatal("expected unsupported compression error")
	}
	if !strings.Contains(err.Error(), "unsupported compression") {
		t.Fatalf("expected unsupported compression error, got: %v", err)
	}
}
