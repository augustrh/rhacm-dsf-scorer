#!/bin/bash
# Step 7: Demo helpers — generate load and watch scores
# Usage: bash scripts/06-demo.sh [start|stop|watch]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MANIFESTS_DIR="$SCRIPT_DIR/../manifests"
ACTION="${1:-watch}"

case "$ACTION" in
  start)
    echo "=== Starting load generator on dsf-apac ==="
    echo "This will drive CPU usage up, lowering dsf-apac's score."
    oc apply -f "$MANIFESTS_DIR/load-generator.yaml"
    echo "Load generator applied. Watch scores shift with: bash scripts/06-demo.sh watch"
    ;;
  stop)
    echo "=== Stopping load generator ==="
    oc delete -f "$MANIFESTS_DIR/load-generator.yaml" --ignore-not-found
    echo "Load generator removed. Scores will recover within ~60s."
    ;;
  watch)
    echo "=== Watching AddOnPlacementScores (Ctrl+C to stop) ==="
    echo ""
    oc get addonplacementscores -A --watch
    ;;
  scores)
    echo "=== Current scores ==="
    for cluster in dsf-1 dsf-2 dsf-apac; do
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
    echo "Usage: bash scripts/06-demo.sh [start|stop|watch|scores]"
    echo "  start  — apply load generator to dsf-apac"
    echo "  stop   — remove load generator"
    echo "  watch  — live-stream AddOnPlacementScores"
    echo "  scores — snapshot current scores"
    ;;
esac
