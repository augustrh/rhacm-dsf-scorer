# rhacm-dsf-scorer

A sample scoring plugin for the [OCM Dynamic Scoring Framework](https://github.com/open-cluster-management-io/addon-contrib/tree/main/dynamic-scoring-framework) to work with ACM. Scores managed clusters based on CPU idle capacity queried from Prometheus via Thanos.

## What it does

The scorer runs as a deployment on each managed cluster (deployed via ManifestWork from the hub) and exposes an HTTP endpoint returning a placement score based on real-time CPU availability. The hub's DSF addon reads these scores and feeds them into ACM Placement decisions.

## Structure

```
app/                  Python scorer application
  main.py             HTTP server, Prometheus query, score calculation
  schemas/            Pydantic models for DSF scoring API
manifests/
  dynamicscorer.yaml          DSF DynamicScorer CR (hub)
  dynamicscoringconfig.yaml   DSF config (hub)
  manifestwork.yaml.example   ManifestWork template (copy and fill in before use)
  load-generator.yaml         Optional load generator for testing
Dockerfile
```

## Usage

1. Build the image from the `Dockerfile` and push it to your own registry:
   ```bash
   docker build -t your-registry/rhacm-dsf-scorer:latest .
   docker push your-registry/rhacm-dsf-scorer:latest
   ```
2. Copy `manifests/manifestwork.yaml.example` to `manifests/manifestwork.yaml`
3. Fill in `<YOUR_MANAGED_CLUSTER_NAME>`, `<YOUR_PROMETHEUS_SERVICE_ACCOUNT_TOKEN>`, and `<YOUR_CLUSTER_DOMAIN>`
4. Update the `image:` field in `manifestwork.yaml` to point to your registry
5. Apply the ManifestWork from the hub — it deploys the scorer onto the managed cluster
6. Apply `dynamicscorer.yaml` and `dynamicscoringconfig.yaml` on the hub to register the scorer with DSF

## Prerequisites

- RHACM 2.10+ with DSF addon enabled
- Managed clusters with OpenShift monitoring (Thanos Querier) available
