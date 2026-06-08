# Payload Envelope Contract

## Purpose

This document defines the OKPS envelope contract shared by producer, collector, and consumer services.
The canonical schema is `proto/okps/envelope.proto`.

## Envelope Fields

- `message_id` (string): unique message identifier.
- `producer_id` (string): producer instance identifier.
- `created_at_unix_ms` (int64): message creation time in Unix milliseconds.
- `compression` (enum): compression format.
- `original_size_bytes` (uint64): uncompressed payload size.
- `compressed_size_bytes` (uint64): compressed payload size.
- `payload` (bytes): compressed payload bytes.

## Compression Compatibility

Supported compression enum values:
- `COMPRESSION_GZIP`
- `COMPRESSION_ZSTD`

Compatibility notes:
- New enum values must be added with new numeric identifiers and consumers must treat unknown values as unsupported until explicitly implemented.
- Existing field numbers must never be reused.
- New optional fields must use new field numbers and preserve backward compatibility by keeping existing fields and semantics unchanged.

## Validation Rules

For configured bounds `payload_min_bytes` and `payload_max_bytes`:
- `payload_min_bytes <= original_size_bytes <= payload_max_bytes`
- `compression` must be `COMPRESSION_GZIP` or `COMPRESSION_ZSTD`

## OTLP Trace Attribute Mapping

Consumer OTLP gRPC decoding maps span attributes to envelope fields:

- `okps.message_id` -> `message_id`
- `okps.producer_id` -> `producer_id`
- `okps.created_at_unix_ms` -> `created_at_unix_ms`
- `okps.compression` -> `compression` (`gzip`/`COMPRESSION_GZIP`, `zstd`/`COMPRESSION_ZSTD`)
- `okps.original_size_bytes` -> `original_size_bytes`
- `okps.compressed_size_bytes` -> `compressed_size_bytes`
- `okps.payload` -> `payload` (bytes or non-empty string)

If attributes are missing, malformed, or include unsupported compression values, the consumer increments `okps_consumer_decode_errors_total` and continues processing subsequent messages.

## Examples

### Valid Envelope (JSON-style)

```json
{
  "message_id": "msg-101",
  "producer_id": "producer-1",
  "created_at_unix_ms": 1760000000000,
  "compression": "COMPRESSION_ZSTD",
  "original_size_bytes": 1024,
  "compressed_size_bytes": 420,
  "payload": "<bytes>"
}
```

### Invalid Envelope: original_size_bytes below minimum

```json
{
  "message_id": "msg-102",
  "producer_id": "producer-1",
  "created_at_unix_ms": 1760000000001,
  "compression": "COMPRESSION_GZIP",
  "original_size_bytes": 63,
  "compressed_size_bytes": 50,
  "payload": "<bytes>"
}
```

If `payload_min_bytes` is `64`, this envelope is invalid.
