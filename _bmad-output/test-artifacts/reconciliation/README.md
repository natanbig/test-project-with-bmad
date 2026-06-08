# Reconciliation Gate Artifacts

This folder stores US-008 reconciliation gate outputs.

Generated files:

- `reconciliation-<timestamp>.json`: machine-readable gate result.
- `reconciliation-<timestamp>.txt`: human-readable gate result.
- `latest.json`: last generated JSON report.
- `latest.txt`: last generated text report.

Generation command:

```bash
./scripts/validate-reconciliation.sh
```

Required environment (optional overrides):

- `PROMETHEUS_URL` (default: `http://localhost:9090`)
- `METRICS_WINDOW` (default: `5m`)
- `METRICS_VALIDATION_TOLERANCE_PERCENT` (default: `0.5`)
- `SCRAPE_INTERVAL_SECONDS` (default: `10`)
- `OUTPUT_DIR` (default: `_bmad-output/test-artifacts/reconciliation`)