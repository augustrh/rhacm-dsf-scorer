# Scripts

All scripts read from `clusters.conf` at the repo root. No cluster names are hardcoded.

Run in order, or use `setup-all.sh` for the full sequence.

| Script | What it does |
|--------|-------------|
| `extract-kubeconfigs.sh` | Pulls kubeconfigs from Hive secrets to `/tmp/<cluster>-kubeconfig.yaml` |
| `01-build-and-push.sh` | Builds the scorer image and pushes to Quay |
| `02-install-addon.sh` | Helm-installs the DSF addon on the hub |
| `03-deploy-scorer.sh` | Generates ManifestWorks from template and deploys scorer to managed clusters |
| `04-register-scorer.sh` | Applies DynamicScorer + DynamicScoringConfig on the hub |
| `05-verify.sh` | Checks pods, routes, configs, and scores across all clusters |
| `06-demo.sh` | Demo helpers: `start`/`stop` load generator, `watch`/`scores` |
| `dashboard.sh` | Polls scores and writes JSON for the HTML dashboard |
| `setup-all.sh` | Runs everything end-to-end |

## New environment setup

Edit `clusters.conf` — one line per managed cluster:

```
# name:region:bias
tokyo-dsf:ap-northeast-1:15
singapore-dsf:ap-southeast-1:0
useast-dsf:us-east-1:0
uswest-dsf:us-west-2:-10
```

That's it. All scripts, the dashboard, and ManifestWork generation read from this file.
