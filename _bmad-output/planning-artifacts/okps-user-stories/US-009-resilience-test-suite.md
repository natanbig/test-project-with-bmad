# US-009: Resilience Test Suite (Restart and Network Interruption)

## User Story
As a reliability engineer, I want repeatable resilience tests so that collector and consumer failures can be validated against recovery expectations.

## Acceptance Criteria

- Test cases cover collector restart under sustained load.
- Test cases cover consumer scale-down and scale-up rebound.
- Test cases cover temporary network interruption between collector and consumer.
- Recovery timeline and message loss deltas are captured.
- Reconciliation still meets tolerance after recovery window.

## Files to Create

- tests/resilience/collector-restart.md
- tests/resilience/consumer-rebound.md
- tests/resilience/network-interruption.md
- scripts/resilience/run-resilience-suite.sh
- _bmad-output/test-artifacts/resilience/README.md

## Files to Change

- docs/operations/deploy.md
- docs/monitoring/queries.md
- README.md

## Dependencies

- US-006
- US-008
