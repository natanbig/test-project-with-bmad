# US-003: Consumer Service (Go) with Envelope Validation

## User Story
As an SRE, I want consumer pods to receive and validate exported envelopes so that downstream integrity and decoding errors are observable.

## Acceptance Criteria

- Consumer receives OTLP gRPC traffic from collector.
- Envelope fields are decoded and validated against contract rules.
- Consumer tracks decode failures and continues processing next messages.
- Consumer exposes metrics: okps_consumer_messages_received_total and okps_consumer_decode_errors_total.
- Unit tests cover valid decode, invalid envelope, and unsupported compression values.

## Files to Create

- cmd/consumer/main.go
- internal/consumer/config.go
- internal/consumer/receiver_otlp.go
- internal/consumer/decoder.go
- internal/consumer/validator.go
- internal/consumer/metrics.go
- internal/consumer/decoder_test.go
- internal/consumer/validator_test.go

## Files to Change

- go.mod
- Makefile
- README.md
- docs/contracts/payload-contract.md

## Dependencies

- US-001
