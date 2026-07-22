# rhacm-dsf-scorer

A sample scoring plugin for the [OCM Dynamic Scoring Framework](https://github.com/open-cluster-management-io/dynamic-scoring-framework) (DSF) running on Red Hat Advanced Cluster Management. Scores managed clusters based on real-time CPU idle capacity **and** configurable region-aware bias — so Placement can prefer clusters closer to your end users.

Built for the KubeCon Japan 2026 booth demo: [Your Fleet, Your Rules](https://events.linuxfoundation.org/kubecon-cloudnativecon-japan/).

## What it does

The scorer runs as a deployment on each managed cluster and exposes an HTTP endpoint that:

1. **Queries Prometheus** (via Thanos Querier) for real-time CPU idle percentage across nodes
2. **Applies a region bias** — a configurable per-region score adjustment (e.g. +15 for `ap-northeast-1`) that lets you express placement preferences like "prefer clusters near Tokyo"
3. **Returns a score 0–100** that DSF publishes as an `AddOnPlacementScore` on the hub

Placement uses these scores alongside its built-in prioritizers (Balance, Steady, Allocatable CPU/Memory) to decide where workloads land.

### Why region bias?

CPU idle tells you which cluster has capacity. But capacity isn't the only thing that matters — latency, data residency, cost, and compliance all factor into real-world placement. The region bias is a simple example of **external context** shaping placement decisions. Your scorer could call any external API (cost feeds, carbon indexes, compliance engines, MCP servers) before returning a score. DSF doesn't care where the number comes from — it just publishes it.

## How it works

```
┌─────────────────────────────────────────────┐
│  Managed Cluster (e.g. ap-northeast-1)      │
│                                             │
│  Prometheus ──► Scorer ──► Score (0-100)    │
│  (CPU idle)     + region bias               │
│                                             │
└──────────────────────┬──────────────────────┘
                       │
                       ▼
              AddOnPlacementScore
              (published to hub)
                       │
                       ▼
              Placement Decision
              (best cluster wins)
```

## Structure

```
app/
  main.py               Scorer: Prometheus query + region bias + HTTP API
  schemas/
    scoring.py           Pydantic models for DSF scoring API
    config.py            Pydantic models for DSF config API
manifests/
  dynamicscorer.yaml           DynamicScorer CR (apply on hub)
  dynamicscoringconfig.yaml    DynamicScoringConfig CR (apply on hub)
  manifestwork.yaml.example    ManifestWork template (one per managed cluster)
  load-generator.yaml          Optional: generate CPU load for testing
Dockerfile
```

## Quick start

### 1. Build and push

```bash
docker build -t your-registry/rhacm-dsf-scorer:latest .
docker push your-registry/rhacm-dsf-scorer:latest
```

### 2. Deploy to each managed cluster

Copy the ManifestWork template and fill in your values:

```bash
cp manifests/manifestwork.yaml.example manifests/manifestwork.yaml
```

Edit `manifestwork.yaml`:
- `<YOUR_MANAGED_CLUSTER_NAME>` — the cluster namespace on the hub
- `<YOUR_PROMETHEUS_SERVICE_ACCOUNT_TOKEN>` — generate with:
  ```bash
  kubectl create token rhacm-scorer -n dynamic-scoring --duration=8760h
  ```
- `<YOUR_CLUSTER_DOMAIN>` — the cluster's apps domain
- `<YOUR_CLUSTER_REGION>` — the AWS region (or any string you define)
- `REGION_BIAS` — JSON map of region-to-bias values

Apply from the hub:

```bash
oc apply -f manifests/manifestwork.yaml
```

Repeat for each managed cluster (different cluster name, token, domain, and region).

### 3. Register with DSF on the hub

```bash
oc apply -f manifests/dynamicscorer.yaml
oc apply -f manifests/dynamicscoringconfig.yaml
```

### 4. Watch scores flow

```bash
oc get addonplacementscores -A --watch
```

## Configuration

All configuration is via environment variables on the scorer deployment:

| Variable | Default | Description |
|----------|---------|-------------|
| `PROMETHEUS_HOST` | `https://thanos-querier.openshift-monitoring.svc:9091` | Prometheus/Thanos endpoint |
| `PROMETHEUS_QUERY` | `avg by (node) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100` | PromQL query |
| `CLUSTER_REGION` | _(empty)_ | Region identifier for this cluster (e.g. `ap-northeast-1`) |
| `REGION_BIAS` | `{}` | JSON map of region-to-score-bias (e.g. `{"ap-northeast-1": 15, "us-east-1": 0}`) |

### Example: prefer Tokyo

Deploy to two clusters with:
- **Japan cluster**: `CLUSTER_REGION=ap-northeast-1`, `REGION_BIAS={"ap-northeast-1": 15, "us-east-1": 0}`
- **US cluster**: `CLUSTER_REGION=us-east-1`, `REGION_BIAS={"ap-northeast-1": 15, "us-east-1": 0}`

Both clusters idle? Japan scores 15 points higher. Both clusters busy? Japan still gets the edge. Generate load on Japan until its CPU advantage drops below 15 points? US wins. That's the demo.

## Prerequisites

- RHACM 2.16+ with DSF addon enabled (DSF is Developer Preview in ACM 2.16)
- Managed clusters with OpenShift monitoring (Thanos Querier)
- The [Dynamic Scoring Framework](https://github.com/open-cluster-management-io/dynamic-scoring-framework) addon installed on the hub

## How this was built

This scorer was developed iteratively using AI-assisted coding (Claude Code). The process:

1. **Started with the gap**: ACM Placement has the `AddOnPlacementScore` API, but nothing producing custom scores from real-world data.
2. **Built the CPU scorer first**: A minimal Flask/FastAPI app that queries Prometheus and returns a score. ~50 lines of Python.
3. **Added region bias**: A few lines to express "prefer clusters near our users" — demonstrating that your scorer can incorporate any external signal, not just metrics.
4. **Packaged for DSF**: Dockerfile, ManifestWork for hub-driven deployment, DynamicScorer/Config CRs.
5. **Iterated on the demo story**: The scorer exists to show that DSF turns Placement from "score with what we give you" into "score with whatever matters to your business."

The entire scorer is ~80 lines of Python. The framework does the heavy lifting.

## Related

- [Dynamic Scoring Framework](https://github.com/open-cluster-management-io/dynamic-scoring-framework) — the upstream OCM addon
- [Open Cluster Management](https://open-cluster-management.io) — the upstream project
- [Red Hat ACM](https://www.redhat.com/en/technologies/management/advanced-cluster-management) — the downstream product
- [KubeCon Japan 2026 session](https://kubecon-cloudnativecon-japan-2026.sessionize.com/session/1192623) — "Score-Driven Multi-Cluster Management" by Kazuma Takeuchi (SoftBank) and Joydeep Banerjee (Red Hat)
