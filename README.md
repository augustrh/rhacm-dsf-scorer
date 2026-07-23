# DSF Scorer Demo

A working demo of a custom scoring plugin for the [OCM Dynamic Scoring Framework](https://github.com/open-cluster-management-io/dynamic-scoring-framework) (DSF) on Red Hat Advanced Cluster Management.

Scores managed clusters by combining **real-time CPU capacity** with **region-aware business policy** — then DSF publishes those scores as `AddOnPlacementScores` so Placement can route workloads to the best cluster automatically.

Built for the KubeCon Japan 2026 booth demo: [Your Fleet, Your Rules](https://events.linuxfoundation.org/kubecon-cloudnativecon-japan/).

## The demo in 30 seconds

Three managed clusters in different AWS regions. Each gets a scorer that reads CPU idle from Prometheus and applies a configurable region bias:

```
$ bash scripts/06-demo.sh scores

--- dsf-1 ---
  us-east-1: 84        (base 84, bias +0)

--- dsf-2 ---
  us-west-2: 75        (base 85, bias -10)

--- dsf-apac ---
  ap-northeast-1: 100  (base 85, bias +15, capped)
```

Generate CPU load on the Tokyo cluster and watch its score drop in real time. When it falls below the US clusters, Placement flips — workloads move away from Tokyo. Stop the load and Tokyo wins again.

CPU idle tells you **capacity**. Region bias tells you **preference**. Your scorer can call any external signal — cost feeds, carbon indexes, compliance engines — before returning a score. DSF doesn't care where the number comes from.

## How it works

```
                          Hub
                           │
                    DynamicScorer CR
                    (configURL → /config)
                           │
              ┌────────────┼────────────┐
              ▼            ▼            ▼
         ┌─────────┐ ┌─────────┐ ┌─────────┐
         │  dsf-1  │ │  dsf-2  │ │dsf-apac │
         │us-east-1│ │us-west-2│ │ap-ne-1  │
         ├─────────┤ ├─────────┤ ├─────────┤
         │Prom─►Agent│Prom─►Agent│Prom─►Agent
         │    ↓     │ │    ↓     │ │    ↓     │
         │ Scorer   │ │ Scorer   │ │ Scorer   │
         │ bias: +0 │ │ bias:-10 │ │ bias:+15 │
         └────┬─────┘ └────┬─────┘ └────┬─────┘
              │            │            │
              ▼            ▼            ▼
         AddOnPlacementScore (per cluster on hub)
                           │
                    Placement Decision
                    (highest score wins)
```

1. The DSF agent on each cluster queries local Prometheus for CPU idle
2. Agent sends that data to the scorer's `/scoring` endpoint
3. Scorer detects the cluster's AWS region from the Prometheus instance labels and applies the configured bias
4. Agent publishes the biased score as an `AddOnPlacementScore` on the hub
5. Placement uses the scores to pick the best cluster

## Quick start

### Prerequisites

- RHACM 2.13+ with the [DSF addon](https://github.com/open-cluster-management-io/dynamic-scoring-framework) installed
- 2+ managed clusters with OpenShift monitoring
- `oc` CLI logged into the hub cluster
- A container registry you can push to (default: `quay.io/augustrh/rhacm-dsf-scorer`)

### Run it

```bash
git clone https://github.com/augustrh/rhacm-dsf-scorer.git
cd rhacm-dsf-scorer

# Extract managed cluster kubeconfigs from Hive secrets
bash scripts/extract-kubeconfigs.sh

# Build, deploy, register, verify — everything
bash scripts/setup-all.sh
```

Or run each step individually — see [`scripts/README.md`](scripts/README.md).

### Demo day

```bash
bash scripts/06-demo.sh scores       # snapshot current scores
bash scripts/06-demo.sh start        # generate load on dsf-apac
bash scripts/06-demo.sh watch        # live-stream score changes
bash scripts/06-demo.sh stop         # remove load generator
```

## Customize for your environment

The scripts auto-discover cluster domains and generate tokens at runtime. The only thing you configure manually:

**Map your cluster names to AWS regions** in `scripts/03-deploy-scorer.sh`:

```bash
get_region() {
  case "$1" in
    my-east-cluster)  echo "us-east-1" ;;
    my-west-cluster)  echo "us-west-2" ;;
    my-apac-cluster)  echo "ap-northeast-1" ;;
    *)                echo "unknown" ;;
  esac
}
```

Then create a `manifests/manifestwork-<cluster-name>.yaml` for each cluster (copy an existing one, change the `namespace`).

## Configuration

Environment variables on the scorer deployment (set in ManifestWork):

| Variable | Default | Description |
|----------|---------|-------------|
| `PROMETHEUS_HOST` | `https://thanos-querier.openshift-monitoring.svc:9091` | Prometheus/Thanos endpoint |
| `PROMETHEUS_QUERY` | `avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100` | PromQL query |
| `CLUSTER_REGION` | _(empty)_ | Fallback region if detection from Prometheus labels fails |
| `REGION_BIAS` | `{}` | JSON map of region-to-score-bias (e.g. `{"ap-northeast-1": 15}`) |

## Structure

```
app/
  main.py                          Scorer (~100 lines of Python)
  schemas/                         Pydantic models for DSF API
manifests/
  manifestwork-dsf-{1,2,apac}.yaml ManifestWork per managed cluster
  dynamicscorer.yaml               DynamicScorer CR (hub)
  dynamicscoringconfig.yaml        DynamicScoringConfig CR (hub)
  load-generator.yaml              CPU stress pod for demo
scripts/                           Automation (see scripts/README.md)
Dockerfile
```

## Related

- [Dynamic Scoring Framework](https://github.com/open-cluster-management-io/dynamic-scoring-framework) — the upstream OCM addon
- [Open Cluster Management](https://open-cluster-management.io) — the upstream project
- [Red Hat ACM](https://www.redhat.com/en/technologies/management/advanced-cluster-management) — the downstream product
