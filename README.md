# DSF Scorer Demo

A working demo of a custom scoring plugin for the [OCM Dynamic Scoring Framework](https://github.com/open-cluster-management-io/dynamic-scoring-framework) (DSF) on Red Hat Advanced Cluster Management.

Scores managed clusters by combining **real-time CPU capacity** with **region-aware business policy** — then DSF publishes those scores as `AddOnPlacementScores` so Placement can route workloads to the best cluster automatically.

Built for the KubeCon Japan 2026 booth demo: [Your Fleet, Your Rules](https://events.linuxfoundation.org/kubecon-cloudnativecon-japan/).

## The demo in 30 seconds

Four managed clusters in different AWS regions. Each gets a scorer that reads CPU idle from Prometheus, detects the region, and applies a configurable bias plus live policy:

```
$ bash scripts/06-demo.sh scores

--- tokyo-dsf ---
  ap-northeast-1: 100   (bias +15, capped)

--- singapore-dsf ---
  ap-southeast-1: 85

--- useast-dsf ---
  us-east-1: 84         (bias +0)

--- uswest-dsf ---
  us-west-2: 75         (bias -10)
```

Block a region with one API call (data sovereignty). Penalize another (cloud provider issues). Generate load and watch scores shift in real time. The fleet adapts — no redeploy, no restart.

CPU idle tells you **capacity**. Region bias tells you **preference**. The `/policy` endpoint tells you **what's allowed right now**. Your scorer can call any external signal — cost feeds, carbon indexes, compliance engines — before returning a score. DSF doesn't care where the number comes from.

## How it works

```
                          Hub
                           │
                    DynamicScorer CR
                    (configURL → /config)
                           │
          ┌────────┬───────┼───────┬────────┐
          ▼        ▼       ▼       ▼        ▼
     ┌────────┐┌────────┐┌────────┐┌────────┐
     │tokyo   ││singapore││useast ││uswest  │
     │ap-ne-1 ││ap-se-1  ││us-e-1 ││us-w-2  │
     ├────────┤├────────┤├────────┤├────────┤
     │Prom─►Ag││Prom─►Ag││Prom─►Ag││Prom─►Ag│
     │   ↓    ││   ↓    ││   ↓    ││   ↓    │
     │ Scorer ││ Scorer ││ Scorer ││ Scorer │
     └───┬────┘└───┬────┘└───┬────┘└───┬────┘
         │         │         │         │
         ▼         ▼         ▼         ▼
     AddOnPlacementScore (per cluster on hub)
                           │
                    Placement Decision
                    (highest score wins)
```

1. The DSF agent on each cluster queries local Prometheus for CPU idle
2. Agent sends that data to the scorer's `/scoring` endpoint
3. Scorer detects the cluster's AWS region from the Prometheus instance labels and applies bias + live policy
4. Agent publishes the score as an `AddOnPlacementScore` on the hub
5. Placement uses the scores to pick the best cluster

## Quick start

### Prerequisites

- RHACM 2.13+ with the [DSF addon](https://github.com/open-cluster-management-io/dynamic-scoring-framework) installed
- 2+ managed clusters with OpenShift monitoring
- `oc` CLI logged into the hub cluster
- A container registry you can push to (default: `quay.io/augustrh/rhacm-dsf-scorer`)

### Configure

Edit `clusters.conf` — one line per managed cluster:

```
# name:region:bias
tokyo-dsf:ap-northeast-1:15
singapore-dsf:ap-southeast-1:0
useast-dsf:us-east-1:0
uswest-dsf:us-west-2:-10
```

That's the only file you edit. All scripts read from it.

### Deploy

```bash
git clone https://github.com/augustrh/rhacm-dsf-scorer.git
cd rhacm-dsf-scorer

# Full setup: extract kubeconfigs, build, deploy, register, verify
bash scripts/setup-all.sh
```

Or run each step individually — see [`scripts/README.md`](scripts/README.md).

### Demo day

```bash
bash scripts/06-demo.sh scores             # snapshot current scores
bash scripts/06-demo.sh start tokyo-dsf     # generate load on a cluster
bash scripts/06-demo.sh watch              # live-stream score changes
bash scripts/06-demo.sh stop tokyo-dsf      # remove load generator
```

### Live policy control

Block regions, penalize regions, or both — at runtime with curl:

```bash
# Get the scorer URL
SCORER=$(KUBECONFIG="/tmp/tokyo-dsf-kubeconfig.yaml" \
  oc get route rhacm-scorer -n dynamic-scoring -o jsonpath='http://{.spec.host}')

# Block Singapore (data sovereignty)
curl -s -X POST $SCORER/policy \
  -H 'Content-Type: application/json' \
  -d '{"blocked": ["ap-southeast-1"]}'

# Penalize us-east-1 (cloud provider issues)
curl -s -X POST $SCORER/policy \
  -H 'Content-Type: application/json' \
  -d '{"blocked": ["ap-southeast-1"], "adjustments": {"us-east-1": -30}}'

# Clear all policy
curl -s -X DELETE $SCORER/policy
```

### Dashboard

A live HTML dashboard shows placement scores as vertical bars, updating every 5 seconds:

```bash
bash scripts/dashboard.sh                    # Terminal 1: polls scores
cd dashboard && python3 -m http.server 8080  # Terminal 2: serves dashboard
# Open http://localhost:8080
```

The dashboard is data-driven — it renders whatever clusters appear in `scores.json`.

## Configuration

Environment variables on the scorer deployment (set via ManifestWork, generated from `clusters.conf`):

| Variable | Default | Description |
|----------|---------|-------------|
| `PROMETHEUS_HOST` | `https://thanos-querier.openshift-monitoring.svc:9091` | Prometheus/Thanos endpoint |
| `PROMETHEUS_QUERY` | `avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100` | PromQL query |
| `CLUSTER_REGION` | _(empty)_ | Fallback region if detection from Prometheus labels fails |
| `REGION_BIAS` | `{}` | JSON map of region-to-score-bias — auto-generated from `clusters.conf` |

## Structure

```
clusters.conf                         Cluster config (name:region:bias)
app/
  main.py                             Scorer + /policy endpoint (~120 lines)
  schemas/                            Pydantic models for DSF API
manifests/
  manifestwork.yaml.example           Template — scripts generate per-cluster copies
  dynamicscorer.yaml                  DynamicScorer CR (hub)
  dynamicscoringconfig.yaml           DynamicScoringConfig CR (hub)
  load-generator.yaml                 CPU stress pod for demo
  generated/                          Runtime-generated ManifestWorks (gitignored)
scripts/
  lib.sh                              Shared helpers — reads clusters.conf
  setup-all.sh                        Full deploy pipeline
  dashboard.sh                        Score poller for HTML dashboard
  (see scripts/README.md)
dashboard/
  index.html                          Live score visualization
DEMO.md                               Four-beat demo run sheet
```

## Related

- [Dynamic Scoring Framework](https://github.com/open-cluster-management-io/dynamic-scoring-framework) — the upstream OCM addon
- [Open Cluster Management](https://open-cluster-management.io) — the upstream project
- [Red Hat ACM](https://www.redhat.com/en/technologies/management/advanced-cluster-management) — the downstream product
