# US-002: Producer Service (Go) with Bounded Payload and OTLP Export

## User Story
As a platform engineer, I want producer pods to generate bounded random compressed packages and export them via OTLP gRPC so that load can be injected into the pipeline in a controlled way.

## Acceptance Criteria

- Producer generates random payloads within configured min and max size.
- Producer compresses payload using configured algorithm (gzip or zstd).
- Producer sends telemetry to collector OTLP endpoint over gRPC.
- Retries use bounded exponential backoff with timeout.
- Producer exposes metrics: okps_producer_messages_sent_total, okps_producer_send_errors_total, okps_producer_payload_bytes_total.
- Unit tests cover payload bounds and compression metadata.

## Files to Create

- cmd/producer/main.go
- internal/producer/config.go
- internal/producer/generator.go
- internal/producer/compress.go
- internal/producer/exporter_otlp.go
- internal/producer/retry.go
- internal/producer/metrics.go
- internal/producer/generator_test.go
- internal/producer/compress_test.go

## Files to Change

- go.mod
- Makefile
- README.md
- docs/contracts/payload-contract.md

## Dependencies

- US-001
