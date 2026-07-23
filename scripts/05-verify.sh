#!/bin/bash
# Step 6: Verify the full DSF scorer deployment
# Usage: bash scripts/05-verify.sh [cluster1 cluster2 ...]
# Default: dsf-1 dsf-2 dsf-apac

set -euo pipefail

CLUSTERS="${@:-dsf-1 dsf-2 dsf-apac}"

echo "=== Step 5: Verify ==="

echo ""
echo "--- DSF Addon Status (hub) ---"
oc get managedclusteraddon -A | grep dynamic-scoring || echo "No dynamic-scoring addons found"

for cluster in $CLUSTERS; do
  KUBECONFIG_FILE="/tmp/${cluster}-kubeconfig.yaml"

  echo ""
  echo "--- $cluster ---"

  if [ ! -f "$KUBECONFIG_FILE" ]; then
    echo "  SKIP: $KUBECONFIG_FILE not found"
    continue
  fi

  # Scorer pod
  echo "  Scorer pod:"
  KUBECONFIG="$KUBECONFIG_FILE" oc get pods -n dynamic-scoring 2>/dev/null | grep rhacm-scorer || echo "    Not found"

  # DSF agent pod
  echo "  DSF agent:"
  KUBECONFIG="$KUBECONFIG_FILE" oc get pods -n dynamic-scoring 2>/dev/null | grep dynamic-scoring-agent || echo "    Not found"

  # Route
  echo "  Route:"
  KUBECONFIG="$KUBECONFIG_FILE" oc get route -n dynamic-scoring 2>/dev/null || echo "    Not found"

  # ConfigMap
  echo "  ConfigMap:"
  KUBECONFIG="$KUBECONFIG_FILE" oc get configmap dynamic-scoring-config -n dynamic-scoring 2>/dev/null && echo "    Present" || echo "    Not found (may take ~1 min)"
done

echo ""
echo "--- AddOnPlacementScores (hub) ---"
oc get addonplacementscores -A 2>/dev/null || echo "None found yet (agent fires every 60s)"

echo ""
echo "=== Verification complete ==="
