import json
import os
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
    'avg by (node) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100',
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


def _apply_region_bias(score: int) -> int:
    bias = REGION_BIAS.get(CLUSTER_REGION, 0)
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
        scores = []
        for r in results:
            metric = r.get("metric", {})
            value = float(r.get("value", [0, 0])[1])
            scores.append({"metric": metric, "score": _apply_region_bias(int(value))})
        return scores
    except Exception as exc:
        print(f"Prometheus query failed: {exc}")
        return []


@app.post("/scoring", response_model=ScoringResponse)
async def scoring(payload: ScoringPayload, request: Request):
    # Query OCP Prometheus directly — the DSF agent may not be able to
    # authenticate with OCP cluster monitoring, so we collect data ourselves
    # using the pod's service account token (requires cluster-monitoring-view).
    scores = _query_prometheus()

    if not scores:
        for series in payload.data:
            values = [float(v[1]) for v in series.values]
            avg = sum(values) / len(values) if values else 0
            scores.append({"metric": series.metric, "score": _apply_region_bias(int(avg))})

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
