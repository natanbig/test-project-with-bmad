# Load and Fairness Test Artifacts (US-010)

This folder stores outputs from load and distribution fairness validation:

- `scripts/load/run-load-tests.sh`
- `scripts/load/calc-fairness.py`

## Generated Files

- `<scenario>-p<producer>-c<collector>-u<consumer>-<timestamp>.json`: machine-readable run report.
- `<scenario>-p<producer>-c<collector>-u<consumer>-<timestamp>.txt`: concise human-readable run report.
- `load-summary-<timestamp>.json`: summary of generated run report paths.
- `load-summary-<timestamp>.txt`: text summary.
- `latest.json`: copy of latest summary JSON.
- `latest.txt`: copy of latest summary text.

## Report Content (Per Run)

- Scenario profile (`steady` or `burst`) and timing.
- Producer/collector/consumer replica mix.
- Total sent/received counters and key receive ratios.
- Per-consumer distribution statistics.
- Fairness metrics including `fairness_score` and `jain_fairness_index`.
- Saturation and bottleneck detection with recommended scaling actions.

## Run

```bash
chmod +x ./scripts/load/run-load-tests.sh ./scripts/load/calc-fairness.py
./scripts/load/run-load-tests.sh
```

Run only steady-state:

```bash
./scripts/load/run-load-tests.sh --scenario tests/load/steady-state.yaml
```

Override replica sets for matrix testing:

```bash
./scripts/load/run-load-tests.sh \
  --producer-replicas 2,4 \
  --collector-replicas 1,2 \
  --consumer-replicas 2,4
```
