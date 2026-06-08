# Collector Load-Balancing Configuration

This folder contains the OTel Collector configuration for US-004.

## What this config does

- Accepts OTLP gRPC ingest on `0.0.0.0:4317`.
- Exports traces to consumer pods discovered through a headless-service DNS name:
  `okps-consumer-headless.okps.svc.cluster.local:4317`.
- Applies runId-affinity load balancing:
  - Promotes span attribute `okps.run_id` to `resource.attributes["service.name"]`.
  - Uses `loadbalancing.routing_key: service` for stable key routing.
- Uses bounded affinity controls:
  - TTL-style refresh bound via `resolver.dns.interval: 5s`.
  - Bounded routing/export buffer via `sending_queue.queue_size: 10000`.
- Emits collector counters as:
  - `okps_collector_messages_received_total`
  - `okps_collector_messages_exported_total`
  - `okps_collector_export_errors_total`

## Validate config

Using Docker with the collector's validate command (dry-run equivalent):

```bash
docker run --rm \
  -v "$PWD/deploy/collector/collector-config.yaml:/etc/otelcol-contrib/config.yaml:ro" \
  otel/opentelemetry-collector-contrib:latest \
  validate --config=/etc/otelcol-contrib/config.yaml
```
