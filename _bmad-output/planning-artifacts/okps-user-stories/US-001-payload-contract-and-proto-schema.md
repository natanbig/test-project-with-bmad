# US-001: Payload Contract and Proto Schema

## User Story
As a platform engineer, I want a strict package envelope contract so that producers, collector, and consumers can interoperate with bounded payload rules.

## Acceptance Criteria

- A protobuf schema defines the envelope fields: message_id, producer_id, created_at_unix_ms, compression, original_size_bytes, compressed_size_bytes, payload.
- Compression enum supports gzip and zstd.
- Validation rules enforce payload_min_bytes <= original_size_bytes <= payload_max_bytes.
- Contract tests cover valid and invalid envelopes.
- Contract documentation includes compatibility notes and examples.

## Files to Create

- proto/okps/envelope.proto
- pkg/contract/validate.go
- pkg/contract/validate_test.go
- docs/contracts/payload-contract.md

## Files to Change

- go.mod
- README.md

## Dependencies

- None
