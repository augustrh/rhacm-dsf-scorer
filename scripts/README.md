# Scripts

Run in order. Each script can also run standalone.

| Script | What it does |
|--------|-------------|
| `extract-kubeconfigs.sh` | Pulls kubeconfigs from Hive secrets to `/tmp/<cluster>-kubeconfig.yaml` |
| `01-build-and-push.sh` | Builds the scorer image and pushes to Quay |
| `02-install-addon.sh` | Helm-installs the DSF addon on the hub |
| `03-deploy-scorer.sh` | Deploys scorer to managed clusters via ManifestWork |
| `04-register-scorer.sh` | Applies DynamicScorer + DynamicScoringConfig on the hub |
| `05-verify.sh` | Checks pods, routes, configs, and scores across all clusters |
| `06-demo.sh` | Demo helpers: `start`/`stop` load generator, `watch`/`scores` |
| `setup-all.sh` | Runs everything end-to-end |

## New environment setup

If your managed clusters have different names, update one thing:

The `get_region()` function in `03-deploy-scorer.sh` — map your cluster names to AWS regions:

```bash
get_region() {
  case "$1" in
    my-cluster-east)  echo "us-east-1" ;;
    my-cluster-west)  echo "us-west-2" ;;
    my-cluster-apac)  echo "ap-northeast-1" ;;
    *)                echo "unknown" ;;
  esac
}
```

Also create a `manifests/manifestwork-<name>.yaml` for each cluster (copy an existing one, change the `namespace` to match your cluster name).
