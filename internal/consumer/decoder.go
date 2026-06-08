package consumer

import (
	"fmt"
	"strconv"
	"strings"

	"github.com/ejh/test-project-with-bmad/pkg/contract"
	commonv1 "go.opentelemetry.io/proto/otlp/common/v1"
	tracev1 "go.opentelemetry.io/proto/otlp/trace/v1"
)

// DecodeEnvelopeFromSpan maps OTLP span attributes to a contract envelope.
func DecodeEnvelopeFromSpan(span *tracev1.Span) (contract.Envelope, error) {
	if span == nil {
		return contract.Envelope{}, fmt.Errorf("span is nil")
	}

	attrs := toAttrMap(span.Attributes)

	messageID, err := getRequiredString(attrs, "okps.message_id")
	if err != nil {
		return contract.Envelope{}, err
	}
	producerID, err := getRequiredString(attrs, "okps.producer_id")
	if err != nil {
		return contract.Envelope{}, err
	}
	createdAtUnixMS, err := getRequiredInt64(attrs, "okps.created_at_unix_ms")
	if err != nil {
		return contract.Envelope{}, err
	}
	compression, err := getCompression(attrs)
	if err != nil {
		return contract.Envelope{}, err
	}
	originalSize, err := getRequiredUint64(attrs, "okps.original_size_bytes")
	if err != nil {
		return contract.Envelope{}, err
	}
	compressedSize, err := getRequiredUint64(attrs, "okps.compressed_size_bytes")
	if err != nil {
		return contract.Envelope{}, err
	}
	payload, err := getRequiredBytes(attrs, "okps.payload")
	if err != nil {
		return contract.Envelope{}, err
	}

	return contract.Envelope{
		MessageID:           messageID,
		ProducerID:          producerID,
		CreatedAtUnixMS:     createdAtUnixMS,
		Compression:         compression,
		OriginalSizeBytes:   originalSize,
		CompressedSizeBytes: compressedSize,
		Payload:             payload,
	}, nil
}

func toAttrMap(attrs []*commonv1.KeyValue) map[string]*commonv1.AnyValue {
	m := make(map[string]*commonv1.AnyValue, len(attrs))
	for _, kv := range attrs {
		if kv == nil || kv.Key == "" {
			continue
		}
		m[kv.Key] = kv.Value
	}
	return m
}

func getRequiredString(attrs map[string]*commonv1.AnyValue, key string) (string, error) {
	v, ok := attrs[key]
	if !ok || v == nil {
		return "", fmt.Errorf("missing required attribute %q", key)
	}
	s := strings.TrimSpace(v.GetStringValue())
	if s == "" {
		return "", fmt.Errorf("attribute %q must be a non-empty string", key)
	}
	return s, nil
}

func getRequiredInt64(attrs map[string]*commonv1.AnyValue, key string) (int64, error) {
	v, ok := attrs[key]
	if !ok || v == nil {
		return 0, fmt.Errorf("missing required attribute %q", key)
	}
	if iv := v.GetIntValue(); iv != 0 {
		return iv, nil
	}
	s := strings.TrimSpace(v.GetStringValue())
	if s == "" {
		return 0, fmt.Errorf("attribute %q must be int64", key)
	}
	parsed, err := strconv.ParseInt(s, 10, 64)
	if err != nil {
		return 0, fmt.Errorf("attribute %q must be int64: %w", key, err)
	}
	return parsed, nil
}

func getRequiredUint64(attrs map[string]*commonv1.AnyValue, key string) (uint64, error) {
	v, ok := attrs[key]
	if !ok || v == nil {
		return 0, fmt.Errorf("missing required attribute %q", key)
	}
	if iv := v.GetIntValue(); iv > 0 {
		return uint64(iv), nil
	}
	s := strings.TrimSpace(v.GetStringValue())
	if s == "" {
		return 0, fmt.Errorf("attribute %q must be uint64", key)
	}
	parsed, err := strconv.ParseUint(s, 10, 64)
	if err != nil {
		return 0, fmt.Errorf("attribute %q must be uint64: %w", key, err)
	}
	return parsed, nil
}

func getRequiredBytes(attrs map[string]*commonv1.AnyValue, key string) ([]byte, error) {
	v, ok := attrs[key]
	if !ok || v == nil {
		return nil, fmt.Errorf("missing required attribute %q", key)
	}
	if b := v.GetBytesValue(); len(b) > 0 {
		return b, nil
	}
	s := v.GetStringValue()
	if s == "" {
		return nil, fmt.Errorf("attribute %q must be non-empty bytes", key)
	}
	return []byte(s), nil
}

func getCompression(attrs map[string]*commonv1.AnyValue) (string, error) {
	raw, err := getRequiredString(attrs, "okps.compression")
	if err != nil {
		return "", err
	}
	switch strings.ToUpper(raw) {
	case "GZIP", "COMPRESSION_GZIP":
		return contract.CompressionGzip, nil
	case "ZSTD", "COMPRESSION_ZSTD":
		return contract.CompressionZstd, nil
	default:
		return "", fmt.Errorf("unsupported compression: %q", raw)
	}
}
