# Collector Routing Architecture

US-004 defines collector routing behavior for producer -> collector -> consumer flow.

## Routing Model

- Ingress protocol: OTLP gRPC receiver on port `4317`.
- Egress protocol: OTLP gRPC exporter to consumer headless service DNS.
- Affinity key: `okps.run_id`.

## Affinity Implementation

1. The transform processor copies `span.attributes["okps.run_id"]` into
   `resource.attributes["service.name"]` when present.
2. The loadbalancing exporter uses `routing_key: service`.
3. This produces stable per-run routing, because all telemetry with the same runId
   resolves to the same routing key.

## Key Cache Bounds

The loadbalancing configuration enforces bounded affinity behavior:

- `resolver.dns.interval: 5s` provides a TTL-style refresh bound for endpoint-to-key mapping updates.
- `sending_queue.queue_size: 10000` bounds queued export work during active routing.

These settings prevent unbounded growth while preserving run-local stickiness.

## Collector Counters

Collector internal telemetry is scraped and transformed into expected reconciliation counters:

- `okps_collector_messages_received_total`
- `okps_collector_messages_exported_total`
- `okps_collector_export_errors_total`

The mapping source metrics are collector internal counters:

- `otelcol_receiver_accepted_spans`
- `otelcol_exporter_sent_spans`
- `otelcol_exporter_send_failed_spans`
