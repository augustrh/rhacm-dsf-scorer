# DSF Scorer Demo — Your Fleet, Your Rules

## The story

ACM Placement can score clusters on resource capacity — but real-world placement decisions aren't just about CPU. They're about **policy**: where your users are, where your data is allowed to live, and what to do when a cloud provider has issues.

This demo shows a custom DSF scorer that combines real-time CPU capacity with live business policy — and how that policy can change with a single API call. No redeploy. No restart. The fleet adapts.

## Setup

You need an ACM hub with four managed clusters matching `clusters.conf`. Everything should be running before the demo starts. Audience sees the dashboard with scores already live.

```bash
# Terminal 1 — feed the dashboard
bash scripts/dashboard.sh

# Terminal 2 — serve the dashboard
cd dashboard && python3 -m http.server 8080
# Open http://localhost:8080

# Terminal 3 — your demo terminal (curl + demo commands)
```

Note the scorer Route URL (all policy calls go here):
```bash
# Get the scorer route from the first cluster
SCORER=$(KUBECONFIG="/tmp/$(head -1 clusters.conf | grep -v '^#' | cut -d: -f1)-kubeconfig.yaml" \
  oc get route rhacm-scorer -n dynamic-scoring -o jsonpath='http://{.spec.host}')
echo $SCORER
```

## Beat 1 — Bias holds

**Start in the ACM console.** Click around. Show the audience the product.

1. **Clusters page** — show all four managed clusters in Ready state
2. **Add-ons tab** — click into a cluster, show "dynamic-scoring" listed as an installed addon
3. **Switch to the dashboard** — now show the live scores

> "This is Advanced Cluster Management. Four clusters across AWS regions — Tokyo, Singapore, US East, US West. You can see Dynamic Scoring is installed as an addon on each one. It's part of the product. Now let's look at what it's actually doing."

**What the audience sees:** Dashboard with four clusters, different scores. Tokyo (ap-northeast-1) is winning.

> "All four clusters have similar CPU capacity. But Tokyo scores highest because our business policy says our users are in Japan — we want workloads there. This isn't a config flag on Placement. It's custom logic in a scorer we wrote. About 100 lines of Python."

No commands needed. Console + dashboard.

## Beat 2 — Data sovereignty

**What you say:**
> "Now legal tells us Singapore can't host this workload. Data sovereignty. One API call."

```bash
curl -s -X POST $SCORER/policy \
  -H 'Content-Type: application/json' \
  -d '{"blocked": ["ap-southeast-1"]}'
```

**What the audience sees:** Singapore drops to 0 despite having great capacity.

> "Singapore had the best capacity in the fleet. Doesn't matter — policy says no. No Placement rule can do this today. Your scorer can."

Wait ~60s for scores to update.

## Beat 3 — Protected under load

**What you say:**
> "What if Tokyo gets busy? Does the next placement land in Singapore?"

```bash
bash scripts/06-demo.sh start tokyo-dsf
```

**What the audience sees:** Tokyo's score drops. US clusters move up in the ranking. Singapore stays at 0.

> "Tokyo is under load so its score drops. The next best clusters rise in the ranking, but Singapore stays at zero. Blocked means blocked. Placement will never pick it."

Let it run for ~90s so scores visibly shift.

## Beat 4 — Cloud provider issues

**What you say:**
> "Now your cloud provider is having issues in us-east-1."

```bash
curl -s -X POST $SCORER/policy \
  -H 'Content-Type: application/json' \
  -d '{"blocked": ["ap-southeast-1"], "adjustments": {"us-east-1": -30}}'
```

**What the audience sees:** us-east-1 drops. us-west-2 becomes the top option (with Tokyo still under load and Singapore blocked).

> "One API call. No tickets, no manual intervention. Your fleet adapts to what's happening right now."

## Reset

```bash
# Clear all policy
curl -s -X DELETE $SCORER/policy

# Stop load generator
bash scripts/06-demo.sh stop tokyo-dsf
```

Scores recover within ~60s.

## Punchline

> "Everything you just saw is driven by ~100 lines of Python. The scorer queries Prometheus for CPU, detects the region, applies your business policy, and returns a score. DSF publishes it. Placement acts on it. Your fleet, your rules."

Open the scorer source on screen: https://github.com/augustrh/rhacm-dsf-scorer/blob/main/app/main.py

> "This is it. The whole scorer. One file."

Walk through what they're looking at:

- `/scoring` endpoint -- receives CPU data from the DSF agent, detects the AWS region from Prometheus instance labels, applies bias + live policy, returns a score
- `/policy` endpoint -- the POST/GET/DELETE you just saw blocking regions and penalizing regions at runtime
- `/config` endpoint -- tells DSF where to find Prometheus and how often to score
- `_detect_region()` -- reads EC2 internal DNS patterns to figure out which region the data came from
- `_apply_bias()` -- combines the raw CPU score with region bias, policy blocks, and adjustments

## Timing

| Beat | Duration | Running total |
|------|----------|---------------|
| Setup (pre-demo) | — | — |
| Beat 1: Bias | 30s | 0:30 |
| Beat 2: Sovereignty | 60s (wait for score update) | 1:30 |
| Beat 3: Load + protection | 90s | 3:00 |
| Beat 4: Cloud provider issues | 60s | 4:00 |
| Reset + punchline | 30s | 4:30 |

Total: ~4–5 minutes.

## Quick reference

```bash
# Show current scores
bash scripts/06-demo.sh scores

# Show current policy
curl -s $SCORER/policy | python3 -m json.tool

# Block a region
curl -s -X POST $SCORER/policy \
  -H 'Content-Type: application/json' \
  -d '{"blocked": ["ap-southeast-1"]}'

# Penalize a region
curl -s -X POST $SCORER/policy \
  -H 'Content-Type: application/json' \
  -d '{"adjustments": {"us-east-1": -30}}'

# Both at once
curl -s -X POST $SCORER/policy \
  -H 'Content-Type: application/json' \
  -d '{"blocked": ["ap-southeast-1"], "adjustments": {"us-east-1": -30}}'

# Clear policy
curl -s -X DELETE $SCORER/policy

# Start load on a cluster
bash scripts/06-demo.sh start tokyo-dsf

# Stop load
bash scripts/06-demo.sh stop tokyo-dsf
```
