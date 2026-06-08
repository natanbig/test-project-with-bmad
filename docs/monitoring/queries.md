# OKPS Monitoring Queries

This document defines the PromQL used by the OKPS reconciliation dashboard.

## Variable

- `metrics_window`: configurable range vector used in all `increase(...)` expressions.
- Suggested values: `1m`, `5m`, `15m`, `1h`.

## Core Totals

- producer_sent

```promql
sum(increase(okps_producer_messages_sent_total[$metrics_window]))
```

- collector_received

```promql
sum(increase(okps_collector_messages_received_total[$metrics_window]))
```

- consumers_received

```promql
sum(increase(okps_consumer_messages_received_total[$metrics_window]))
```

## Deltas

- producer_to_collector_delta

```promql
sum(increase(okps_producer_messages_sent_total[$metrics_window]))
- sum(increase(okps_collector_messages_received_total[$metrics_window]))
```

- collector_to_consumer_delta

```promql
sum(increase(okps_collector_messages_received_total[$metrics_window]))
- sum(increase(okps_consumer_messages_received_total[$metrics_window]))
```

## Ratios

- collector_receive_ratio

```promql
sum(increase(okps_collector_messages_received_total[$metrics_window]))
/ clamp_min(sum(increase(okps_producer_messages_sent_total[$metrics_window])), 1)
```

- consumer_receive_ratio

```promql
sum(increase(okps_consumer_messages_received_total[$metrics_window]))
/ clamp_min(sum(increase(okps_producer_messages_sent_total[$metrics_window])), 1)
```

- collector_to_consumer_ratio

```promql
sum(increase(okps_consumer_messages_received_total[$metrics_window]))
/ clamp_min(sum(increase(okps_collector_messages_received_total[$metrics_window])), 1)
```

## Per-Consumer Distribution

Uses the pod label from scrape target relabeling to show receive distribution by consumer pod.

```promql
sum by (pod) (increase(okps_consumer_messages_received_total[$metrics_window]))
```

## Error Counters

```promql
sum(increase(okps_producer_send_errors_total[$metrics_window]))
sum(increase(okps_collector_export_errors_total[$metrics_window]))
sum(increase(okps_consumer_decode_errors_total[$metrics_window]))
```

## Alert Thresholds (US-008)

Thresholds are derived from `metrics_validation_tolerance_percent`.

Given `metrics_validation_tolerance_percent=0.5`:

- critical ratio threshold: `1 - 0.5/100 = 0.995`
- warning ratio threshold: `1 - (0.5/2)/100 = 0.9975`

### Warning Expression

```promql
(
	(
		sum(increase(okps_collector_messages_received_total[5m]))
		/ clamp_min(sum(increase(okps_producer_messages_sent_total[5m])), 1)
	) < 0.9975
	or
	(
		sum(increase(okps_consumer_messages_received_total[5m]))
		/ clamp_min(sum(increase(okps_producer_messages_sent_total[5m])), 1)
	) < 0.9975
)
and sum(increase(okps_producer_messages_sent_total[5m])) > 0
```

### Critical Expression

```promql
(
	(
		sum(increase(okps_collector_messages_received_total[5m]))
		/ clamp_min(sum(increase(okps_producer_messages_sent_total[5m])), 1)
	) < 0.995
	or
	(
		sum(increase(okps_consumer_messages_received_total[5m]))
		/ clamp_min(sum(increase(okps_producer_messages_sent_total[5m])), 1)
	) < 0.995
)
and sum(increase(okps_producer_messages_sent_total[5m])) > 0
```

## Reconciliation Gate Queries (US-008)

The gate script evaluates totals and sustained ratio failures:

- `producer_sent`
- `collector_received`
- `consumers_received`
- `collector_receive_ratio`
- `consumer_receive_ratio`
- sustained critical ratio breach over `2 * scrape_interval`

Sustained failure query pattern:

```promql
(min_over_time((<ratio_expr>)[<2x_scrape_interval>:]) < <critical_ratio>) and (<producer_expr> > 0)
```

Run gate:

```bash
./scripts/validate-reconciliation.sh
```

## Resilience Queries (US-009)

Use these during restart/interruption scenarios to capture recovery timeline and message loss deltas.

### Recovery Timeline Signal

Recovery is considered reached when both relative deltas are within tolerance.

Given `tolerance = metrics_validation_tolerance_percent / 100`:

- producer_to_collector_relative_delta

```promql
abs(
	sum(increase(okps_producer_messages_sent_total[$metrics_window]))
	-
	sum(increase(okps_collector_messages_received_total[$metrics_window]))
)
/
clamp_min(sum(increase(okps_producer_messages_sent_total[$metrics_window])), 1)
```

- collector_to_consumer_relative_delta

```promql
abs(
	sum(increase(okps_collector_messages_received_total[$metrics_window]))
	-
	sum(increase(okps_consumer_messages_received_total[$metrics_window]))
)
/
clamp_min(sum(increase(okps_collector_messages_received_total[$metrics_window])), 1)
```

### Message Loss Delta Signals

Same as panel deltas but sampled across the configured window immediately after fault injection and after recovery.

```promql
sum(increase(okps_producer_messages_sent_total[$metrics_window]))
- sum(increase(okps_collector_messages_received_total[$metrics_window]))

sum(increase(okps_collector_messages_received_total[$metrics_window]))
- sum(increase(okps_consumer_messages_received_total[$metrics_window]))
```

### Fault Window Markers

Use event timestamps from the resilience report (`fault_window_utc.start`, `fault_window_utc.end`) to align query ranges in Grafana Explore and calculate recovery duration as:

$$
	ext{recovery\_seconds} = t_{\text{first in-tolerance sample}} - t_{\text{fault end}}
$$

## Load and Fairness Queries (US-010)

Use these for scale and distribution-fairness validation runs.

### Per-Consumer Distribution (Windowed)

```promql
sum by (pod) (increase(okps_consumer_messages_received_total[$metrics_window]))
```

### Distribution Share by Consumer

```promql
sum by (pod) (increase(okps_consumer_messages_received_total[$metrics_window]))
/
clamp_min(sum(increase(okps_consumer_messages_received_total[$metrics_window])), 1)
```

### Tier Receive Ratios Under Load

```promql
sum(increase(okps_collector_messages_received_total[$metrics_window]))
/
clamp_min(sum(increase(okps_producer_messages_sent_total[$metrics_window])), 1)

sum(increase(okps_consumer_messages_received_total[$metrics_window]))
/
clamp_min(sum(increase(okps_producer_messages_sent_total[$metrics_window])), 1)
```

### Saturation Signal Helpers

```promql
sum(increase(okps_producer_send_errors_total[$metrics_window]))
sum(increase(okps_collector_export_errors_total[$metrics_window]))
sum(increase(okps_consumer_decode_errors_total[$metrics_window]))
```

### Fairness Score Computation

Fairness is computed per run from the per-consumer distribution by `scripts/load/calc-fairness.py` using Jain's fairness index:

$$
J = \frac{\left(\sum_{i=1}^{n} x_i\right)^2}{n \cdot \sum_{i=1}^{n} x_i^2}
$$

Where $x_i$ is the message count for consumer $i$, and $J \in [0, 1]$.
