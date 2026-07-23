import json
import os
import re
import requests
import uvicorn
from fastapi import FastAPI, Request
from schemas.scoring import ScoringPayload, ScoringResponse
from schemas.config import ConfigResponse

PROMETHEUS_HOST = os.getenv(
    "PROMETHEUS_HOST",
    "https://thanos-querier.openshift-monitoring.svc:9091",
)
PROMETHEUS_QUERY = os.getenv(
    "PROMETHEUS_QUERY",
    'avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100',
)
SA_TOKEN_PATH = "/var/run/secrets/kubernetes.io/serviceaccount/token"

CLUSTER_REGION = os.getenv("CLUSTER_REGION", "")
REGION_BIAS = json.loads(os.getenv("REGION_BIAS", "{}"))

app = FastAPI()


def _prometheus_token() -> str:
    try:
        with open(SA_TOKEN_PATH) as f:
            return f.read().strip()
    except FileNotFoundError:
        return os.getenv("PROMETHEUS_TOKEN", "")


def _detect_region(data: list) -> str:
    """Detect AWS region from instance labels in Prometheus payload data.

    AWS internal DNS encodes the region: us-west-2.compute.internal,
    ap-northeast-1.compute.internal.  us-east-1 is the exception — it
    uses .ec2.internal with no region prefix.
    """
    for series in data:
        instance = series.metric.get("instance", "")
        m = re.search(r'\.([a-z]+-[a-z]+-\d+)\.compute\.internal', instance)
        if m:
            return m.group(1)
    for series in data:
        if ".ec2.internal" in series.metric.get("instance", ""):
            return "us-east-1"
    return CLUSTER_REGION or "unknown"


def _apply_bias(score: int, region: str) -> int:
    bias = REGION_BIAS.get(region, 0)
    return max(0, min(100, score + bias))


def _query_prometheus() -> list[dict]:
    token = _prometheus_token()
    headers = {"Authorization": f"Bearer {token}"} if token else {}
    try:
        resp = requests.get(
            f"{PROMETHEUS_HOST}/api/v1/query",
            params={"query": PROMETHEUS_QUERY},
            headers=headers,
            verify=False,
            timeout=10,
        )
        resp.raise_for_status()
        results = resp.json().get("data", {}).get("result", [])
        if not results:
            return []
        values = [float(r.get("value", [0, 0])[1]) for r in results]
        avg_idle = sum(values) / len(values)
        region = CLUSTER_REGION or "unknown"
        cluster_score = _apply_bias(int(avg_idle), region)
        return [{"metric": {"node": region}, "score": cluster_score}]
    except Exception as exc:
        print(f"Prometheus query failed: {exc}")
        return []


@app.post("/scoring", response_model=ScoringResponse)
async def scoring(payload: ScoringPayload, request: Request):
    if payload.data:
        region = _detect_region(payload.data)
        all_values = []
        for series in payload.data:
            all_values.extend(float(v[1]) for v in series.values)
        avg_idle = sum(all_values) / len(all_values) if all_values else 0
        cluster_score = _apply_bias(int(avg_idle), region)
        print(f"Scoring from payload: region={region}, avg_idle={avg_idle:.1f}, bias={REGION_BIAS.get(region, 0)}, score={cluster_score}")
        return {"results": [{"metric": {"node": region}, "score": cluster_score}]}

    scores = _query_prometheus()
    return {"results": scores}


@app.get("/healthz")
async def healthcheck():
    return {"status": "ok"}


@app.get("/config", response_model=ConfigResponse)
async def get_config():
    return {
        "name": "rhacm-cpu-score",
        "description": "Cluster CPU idle score using OCP built-in monitoring (higher = more capacity)",
        "source": {
            "type": "Prometheus",
            "host": PROMETHEUS_HOST,
            "path": "/api/v1/query_range",
            "params": {
                "query": PROMETHEUS_QUERY,
                "range": 300,
                "step": 60,
            },
        },
        "scoring": {
            "path": "/scoring",
            "params": {
                "name": "rhacm-cpu-score",
                "interval": 60,
            },
        },
    }


if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8000)
