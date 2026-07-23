#!/bin/bash
# Extract kubeconfigs for all DSF managed clusters
# Usage: bash scripts/extract-kubeconfigs.sh [cluster1 cluster2 ...]
# Default: all clusters from clusters.conf

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

CLUSTERS="${@:-$(cluster_names)}"

for cluster in $CLUSTERS; do
  secret=$(oc get secrets -n "$cluster" -o name | grep admin-kubeconfig)
  if [ -z "$secret" ]; then
    echo "ERROR: No admin-kubeconfig secret found in namespace $cluster"
    continue
  fi
  echo "[$cluster] Found: $secret"
  oc extract "$secret" -n "$cluster" --to=/tmp --keys=kubeconfig --confirm 2>/dev/null
  mv /tmp/kubeconfig "/tmp/${cluster}-kubeconfig.yaml"
  echo "[$cluster] Saved to /tmp/${cluster}-kubeconfig.yaml"
done
