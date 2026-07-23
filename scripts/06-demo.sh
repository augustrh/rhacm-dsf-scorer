#!/bin/bash
# Step 7: Demo helpers — generate load and watch scores
# Usage: bash scripts/06-demo.sh [start|stop|watch|scores] [cluster]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

MANIFESTS_DIR="$REPO_ROOT/manifests"
ACTION="${1:-watch}"

case "$ACTION" in
  start)
    LOAD_CLUSTER="${2:-$(first_cluster)}"
    LOAD_KUBECONFIG="/tmp/${LOAD_CLUSTER}-kubeconfig.yaml"
    if [ ! -f "$LOAD_KUBECONFIG" ]; then
      echo "ERROR: $LOAD_KUBECONFIG not found. Run scripts/extract-kubeconfigs.sh first."
      exit 1
    fi
    echo "=== Starting load generator on $LOAD_CLUSTER ==="
    echo "This will drive CPU usage up, lowering ${LOAD_CLUSTER}'s score."
    KUBECONFIG="$LOAD_KUBECONFIG" oc apply -f "$MANIFESTS_DIR/load-generator.yaml"
    echo "Load generator applied. Watch scores shift with: bash scripts/06-demo.sh scores"
    ;;
  stop)
    LOAD_CLUSTER="${2:-$(first_cluster)}"
    LOAD_KUBECONFIG="/tmp/${LOAD_CLUSTER}-kubeconfig.yaml"
    echo "=== Stopping load generator on $LOAD_CLUSTER ==="
    KUBECONFIG="$LOAD_KUBECONFIG" oc delete -f "$MANIFESTS_DIR/load-generator.yaml" --ignore-not-found
    echo "Load generator removed. Scores will recover within ~60s."
    ;;
  watch)
    echo "=== Watching AddOnPlacementScores (Ctrl+C to stop) ==="
    echo ""
    oc get addonplacementscores -A --watch
    ;;
  scores)
    echo "=== Current scores ==="
    for cluster in $(cluster_names); do
      echo ""
      echo "--- $cluster ---"
      SCORE_OUTPUT=$(oc get addonplacementscores rhacm-cpu-score -n "$cluster" -o jsonpath='{range .status.scores[*]}  {.name}: {.value}{"\n"}{end}' 2>/dev/null)
      if [ -n "$SCORE_OUTPUT" ]; then
        echo "$SCORE_OUTPUT"
      else
        echo "  No scores yet"
      fi
    done
    ;;
  *)
    echo "Usage: bash scripts/06-demo.sh [start|stop|watch|scores] [cluster]"
    echo "  start [cluster]  — apply load generator (default: $(first_cluster))"
    echo "  stop  [cluster]  — remove load generator"
    echo "  watch            — live-stream AddOnPlacementScores"
    echo "  scores           — snapshot current scores"
    ;;
esac
