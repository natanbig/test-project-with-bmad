---
title: 'Module Plan'
status: 'complete'
module_name: 'OTel Kubernetes Pipeline Suite'
module_code: 'okps'
module_description: 'Plans and scaffolds a Go-based Kubernetes telemetry pipeline with scalable producers, otel-collector load balancing, and scalable consumers over OTLP gRPC.'
architecture: 'hybrid-orchestrator'
standalone: true
expands_module: ''
skills_planned:
  - okps-agent-orchestrator
  - okps-go-producer-consumer-workflow
  - okps-otel-collector-k8s-workflow
  - okps-load-and-resilience-validation-workflow
config_variables:
  - producer_replicas
  - consumer_replicas
  - payload_min_bytes
  - payload_max_bytes
  - compression_algorithm
  - otlp_endpoint
  - deployment_namespace
  - metrics_validation_tolerance_percent
  - metrics_window
created: '2026-06-08T11:14:03Z'
updated: '2026-06-08T11:28:00Z'
---

# Module Plan

## Vision

Build a production-oriented Kubernetes reference system where a scalable chain of producers generates random, bounded-size compressed packages and sends them to otel-collector through OTLP gRPC. The otel-collector tier runs in load-balancing mode and forwards telemetry to downstream consumers through exporters and a headless service strategy. The system emphasizes horizontal scalability, deterministic payload bounds, and Go-native implementation for producer and consumer services.

Primary users:
- Platform engineers validating OTel pipeline architecture at scale
- SRE teams testing collector load distribution and backpressure behavior
- Developers needing a reusable Go baseline for telemetry ingestion and fan-out patterns

## Architecture

Use a hybrid orchestrator pattern:
- One conversational orchestrator agent for intent capture, trade-off guidance, and cross-skill coordination
- Three workflows for deterministic artifact generation and validation

Why this architecture:
- Single-point user experience for planning and changes
- Repeatable generation steps for code and manifests
- Easier maintenance than many specialized agents
- Clear separation between design decisions and executable scaffolding

### Memory Architecture

Pattern: Personal + shared module memory.

- Personal memory for orchestrator decisions and user preferences
- Shared module memory for generated architecture standards, defaults, and validation history

Proposed shared memory structure:
- {project-root}/_bmad/memory/okps-shared/index.md
- {project-root}/_bmad/memory/okps-shared/architecture.md
- {project-root}/_bmad/memory/okps-shared/payload-contract.md
- {project-root}/_bmad/memory/okps-shared/k8s-standards.md
- {project-root}/_bmad/memory/okps-shared/validation-history.md
- {project-root}/_bmad/memory/okps-shared/daily/YYYY-MM-DD.md

### Memory Contract

- index.md
  - Purpose: Entry-point map of shared memory files
  - Read: all skills
  - Write: orchestrator
  - Content: file summaries, last update times, active assumptions

- architecture.md
  - Purpose: Canonical architecture decisions and alternatives considered
  - Read: all workflows
  - Write: orchestrator + collector workflow
  - Content: topology, service boundaries, scaling model

- payload-contract.md
  - Purpose: Payload shape, size bounds, compression rules
  - Read: producer/consumer workflow + validation workflow
  - Write: producer/consumer workflow
  - Content: proto schema, max package size policies, edge-case handling

- k8s-standards.md
  - Purpose: Deployment conventions and networking patterns
  - Read: collector workflow + validation workflow
  - Write: collector workflow
  - Content: namespace, resource quotas, probes, HPA/KEDA guidance, headless service rules

- validation-history.md
  - Purpose: Regression and scale test outcomes
  - Read: orchestrator + validation workflow
  - Write: validation workflow
  - Content: test matrix, throughput distribution, failure modes

- daily/YYYY-MM-DD.md
  - Purpose: append-only daily activity trail
  - Read: orchestrator
  - Write: all skills
  - Content: timestamped actions with skill tag

### Cross-Agent Patterns

- User talks primarily to okps-agent-orchestrator
- Orchestrator routes execution to workflows based on requested outcome
- User may run workflows directly for headless generation
- Workflows write structured artifacts and update shared memory
- Validation workflow consumes generated code/manifests and emits readiness reports back to orchestrator

## Skills

### okps-agent-orchestrator

**Type:** agent

**Persona:** Pragmatic platform architect. Clear, systems-oriented, and explicit about trade-offs (throughput, cost, resiliency, and operational complexity).

**Core Outcome:** Convert user intent into a coherent Go + Kubernetes OTel pipeline plan and coordinate downstream generation/validation workflows.

**The Non-Negotiable:** Preserve protocol correctness (OTLP gRPC) and scalable topology semantics.

**Capabilities:**

| Capability | Outcome | Inputs | Outputs |
| ---------- | ------- | ------ | ------- |
| Requirements Distillation | Converts freeform system goals into explicit technical requirements and constraints | Natural language request, optional SLOs | Requirement brief with assumptions and acceptance criteria |
| Topology Decisioning | Chooses and documents producer-collector-consumer topology with scaling rationale | Requirements brief, traffic profile | Architecture decision record |
| Workflow Orchestration | Routes build tasks to generation and validation workflows in correct order | Requested action, current artifacts | Ordered execution plan and workflow invocations |
| Change Impact Analysis | Assesses impact of changing payload limits, replica counts, or exporters | Existing plan + change request | Impact report (HTML recommended) |

**Memory:** Reads shared index + architecture + validation history on activation. Writes decisions and change logs to architecture.md and daily log.

**Init Responsibility:** Create shared memory index and baseline architecture entry on first run.

**Activation Modes:** Interactive primary; headless supported for deterministic orchestration steps.

**Tool Dependencies:** File tools, terminal for build/test orchestration, optional Kubernetes diagnostics tools.

**Design Notes:** Keep orchestration thin and deterministic. Delegate heavy generation logic to workflows.

---

### okps-go-producer-consumer-workflow

**Type:** workflow

**Core Outcome:** Generate Go producer and consumer services with bounded random payload generation, compression, OTLP gRPC transmission, and downstream decoding/processing.

**The Non-Negotiable:** Payload contract enforcement (size bounds and compression compatibility) under all configured replica counts.

**Capabilities:**

| Capability | Outcome | Inputs | Outputs |
| ---------- | ------- | ------ | ------- |
| Go Service Scaffold | Creates producer/consumer project structure with buildable modules | Module config, service names | Go source tree, go.mod, Makefile |
| Bounded Random Payload Generation | Generates random package content constrained by min/max bytes | payload_min_bytes, payload_max_bytes, seed strategy | Payload generator package and tests |
| Compression Pipeline | Adds gzip or zstd compression/decompression and metadata tagging | compression_algorithm | Compression middleware, compatibility tests |
| OTLP gRPC Integration | Implements producer telemetry export and consumer ingestion contract | otlp_endpoint, proto contract | OTLP client/server integration code |
| Reliability Controls | Adds retries, backoff, deadlines, and observability hooks | retry policy inputs | Resilience utilities and config examples |

**Memory:** Reads payload-contract.md and architecture.md. Writes implementation notes and contract updates to payload-contract.md and daily logs.

**Init Responsibility:** Seed payload contract template with schema, headers, and compatibility matrix.

**Activation Modes:** Interactive and headless.

**Tool Dependencies:** Go toolchain, protoc with Go plugins, optional buf.

**Design Notes:** Keep producer and consumer reusable as independent deployments; avoid hard-coding collector endpoint.

---

### okps-otel-collector-k8s-workflow

**Type:** workflow

**Core Outcome:** Generate Kubernetes manifests and collector config for load-balanced otel-collector deployment with exporters, headless service wiring, and scalable consumers.

**The Non-Negotiable:** Correct collector load-balancing behavior with safe horizontal scaling semantics.

**Capabilities:**

| Capability | Outcome | Inputs | Outputs |
| ---------- | ------- | ------ | ------- |
| Collector Config Authoring | Creates OTEL Collector config with OTLP gRPC receiver, load-balancing exporter, and downstream routing | exporter targets, consumer endpoints | collector-config.yaml |
| K8s Manifest Generation | Produces Deployment/Service/HPA for producers, collectors, and consumers | replica targets, namespace, resources | k8s manifests (YAML or Helm values) |
| Headless Service Topology | Implements headless Services where required for endpoint discovery/load distribution | service topology choices | service manifests and DNS notes |
| Autoscaling Strategy | Configures HPA/KEDA recommendations tied to throughput/latency indicators | scaling goals | autoscaling manifests and tuning guide |
| Operational Hardening | Adds probes, PDB, resource limits, and rollout strategy | reliability policies | production-hardening patch set |

**Memory:** Reads architecture.md and k8s-standards.md. Writes finalized K8s standards and topology rules.

**Init Responsibility:** Initialize namespace and service naming conventions.

**Activation Modes:** Interactive and headless.

**Tool Dependencies:** Kubernetes CLI, Helm or Kustomize (optional), OpenTelemetry Collector distribution.

**Design Notes:** Keep collector config modular so exporters can be swapped without changing producer code.

---

### okps-load-and-resilience-validation-workflow

**Type:** workflow

**Core Outcome:** Validate throughput distribution, load balancing fairness, payload integrity, and resilience under scale and failure scenarios.

**The Non-Negotiable:** Demonstrate that scaling producers/consumers preserves bounded payload correctness and end-to-end delivery guarantees.

**Capabilities:**

| Capability | Outcome | Inputs | Outputs |
| ---------- | ------- | ------ | ------- |
| Functional Validation | Verifies end-to-end package generation, compression, transfer, decompression, and consumption | deployed stack, payload contract | Functional test report |
| Metrics Reconciliation Validation | Verifies end-to-end counts using Grafana/Prometheus metrics for sent, collector-received, and consumers-received totals | metrics_window, producer/collector/consumer labels, tolerance policy | Metrics reconciliation report with pass/fail gate |
| Distribution Fairness Testing | Measures per-consumer message distribution with collector load balancing | replica counts, run duration | Fairness metrics report (HTML recommended) |
| Stress and Burst Testing | Executes high-rate and burst traffic tests for bottleneck detection | load profile config | Stress results with saturation points |
| Failure Injection | Tests collector or consumer restarts/network interruptions | failure scenarios | Resilience report and recovery timelines |
| SLO Gate Evaluation | Compares observed results against target latency/error/SLA thresholds | SLO definitions | Gate decision summary |

**Memory:** Reads architecture + payload + k8s standards. Writes validation-history.md and daily logs.

**Init Responsibility:** Create baseline validation matrix and threshold defaults.

**Activation Modes:** Headless preferred; interactive for analysis.

**Tool Dependencies:** Go test tooling, optional k6/vegeta, kubectl, metrics backend.

**Design Notes:** Produce machine-readable and human-readable outputs to support CI and review workflows.

---

## Configuration

| Variable | Prompt | Default | Result Template | User Setting |
| -------- | ------ | ------- | --------------- | ------------ |
| deployment_namespace | Kubernetes namespace for all pipeline resources? | observability | namespace: {value} | true |
| producer_replicas | Initial producer replica count? | 3 | producers.replicas: {value} | true |
| consumer_replicas | Initial consumer replica count? | 3 | consumers.replicas: {value} | true |
| collector_replicas | Initial otel-collector replica count? | 3 | collectors.replicas: {value} | true |
| payload_min_bytes | Minimum package payload size (bytes)? | 256 | payload.min_bytes: {value} | true |
| payload_max_bytes | Maximum package payload size (bytes)? | 4096 | payload.max_bytes: {value} | true |
| compression_algorithm | Compression algorithm (gzip or zstd)? | gzip | compression: {value} | true |
| otlp_endpoint | OTLP gRPC endpoint for producers? | otel-collector:4317 | otlp.endpoint: {value} | true |
| load_test_duration | Validation run duration (e.g., 5m)? | 5m | validation.duration: {value} | true |
| metrics_window | Metrics reconciliation window (e.g., 5m)? | 5m | metrics.window: {value} | true |
| metrics_validation_tolerance_percent | Allowed delta percent between sent, collector-received, and consumers-received counts | 0.5 | metrics.validation_tolerance_percent: {value} | true |

## External Dependencies

- Go 1.23+ (required by producer/consumer generation workflow)
- Protocol Buffers compiler and Go plugins (for OTLP and custom payload contracts)
- OpenTelemetry Collector image/distribution
- Kubernetes cluster access and kubectl
- Prometheus (or compatible metrics backend) for metric scraping and aggregation
- Grafana for dashboard validation and alerting on count mismatches
- Optional: Helm/Kustomize for packaging manifests
- Optional: k6 or vegeta for load tests

Setup skill handling:
- Verify tool presence
- Print install hints when missing
- Fail fast in headless mode with actionable error output

## UI and Visualization

Recommended optional dashboard:
- Service graph of producer -> collector -> consumer paths
- Per-consumer throughput and distribution variance
- Compression ratio and payload-size histogram
- Error-rate and retry timelines

Required validation dashboard (Grafana):
- Total sent by all producers: `sum(increase(okps_producer_messages_sent_total[{metrics_window}]))`
- Total received by otel-collector: `sum(increase(okps_collector_messages_received_total[{metrics_window}]))`
- Total received by all consumers: `sum(increase(okps_consumer_messages_received_total[{metrics_window}]))`
- Collector receive ratio: `collector_received / producer_sent`
- Consumer receive ratio: `consumers_received / producer_sent`
- Collector-to-consumer ratio: `consumers_received / collector_received`

Validation gate rules:
- Pass when all three totals are monotonic and non-zero during active load.
- Pass when absolute delta between producer_sent and collector_received is within `metrics_validation_tolerance_percent`.
- Pass when absolute delta between collector_received and consumers_received is within `metrics_validation_tolerance_percent`.
- Fail if any ratio drops below `(100 - metrics_validation_tolerance_percent) / 100` for longer than one scrape interval.

Potential output:
- Lightweight static HTML dashboard generated from validation artifacts
- Provisioned Grafana JSON dashboard + alert rules for count mismatch detection

## Setup Extensions

- Scaffold directory layout for go services, proto contracts, manifests, and test suites
- Generate sample .env and values files for local and cluster modes
- Optional bootstrap of namespace and RBAC manifests
- Optional prebuilt Grafana dashboard JSON template
- Provision Prometheus scrape config for producer/collector/consumer metrics endpoints
- Provision Grafana datasource, dashboard, and alerting templates for message count reconciliation

## Integration

This module is standalone and provides immediate value for building and validating a scalable OTel gRPC package pipeline in Kubernetes.

It can later integrate with broader BMad implementation workflows by:
- Feeding generated manifests/code into implementation stories
- Feeding validation outputs into quality/release gates

## Creative Use Cases

- Chaos rehearsal environment for collector topology changes
- Compression algorithm bake-off with real traffic distributions
- Cost/performance optimization experiments by tuning replica ratios
- Canary rollout simulation for collector config changes
- Synthetic telemetry generation for observability platform benchmarking

## Ideas Captured

- Model payload as pseudo-package envelope with metadata + compressed body
- Keep package size bounded before and after compression checks
- Enable configurable producer chains where stage N mutates package fields
- Support both random and seeded deterministic payload streams
- Use headless service for consumer endpoint discovery where collector/exporter model benefits from direct endpoint awareness
- Add fairness score metric to quantify distribution quality
- Include graceful degradation guidance when consumers under-scale versus producer burst
- Reconcile three key counters in Grafana: all producers sent, collector received, all consumers received

## Build Roadmap

1. okps-agent-orchestrator
Rationale: establishes stable requirement/decision flow and shared memory contract used by all workflows.

2. okps-go-producer-consumer-workflow
Rationale: defines payload contract and Go code baseline; downstream collector and validation rely on this.

3. okps-otel-collector-k8s-workflow
Rationale: binds runtime topology to generated services and enables scalable deployment.

4. okps-load-and-resilience-validation-workflow
Rationale: verifies design assumptions and provides release-quality evidence.

**Next steps:**

1. Build each skill using Build an Agent (BA) or Build a Workflow (BW), using this plan as source context.
2. After all skills are built, run Create Module (CM) to scaffold installable module infrastructure.
