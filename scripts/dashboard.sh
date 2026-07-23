#!/bin/bash
# Live dashboard: writes scores to a JSON file that the HTML dashboard reads.
# Usage: bash scripts/dashboard.sh
# Then open dashboard/index.html in a browser.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

DASHBOARD_DIR="$REPO_ROOT/dashboard"
DATA_FILE="$DASHBOARD_DIR/scores.json"

mkdir -p "$DASHBOARD_DIR"

echo "Writing scores to $DATA_FILE every 10s (Ctrl+C to stop)"
echo "Clusters: $(cluster_names)"
echo "Open dashboard/index.html in your browser."
echo ""

while true; do
  JSON='['
  FIRST=true
  for cluster in $(cluster_names); do
    SCORES=$(oc get addonplacementscores rhacm-cpu-score -n "$cluster" \
      -o jsonpath='{range .status.scores[*]}{.name}:{.value},{end}' 2>/dev/null || echo "")
    if [ -n "$SCORES" ]; then
      IFS=',' read -ra PAIRS <<< "$SCORES"
      for pair in "${PAIRS[@]}"; do
        [ -z "$pair" ] && continue
        NAME="${pair%%:*}"
        VALUE="${pair##*:}"
        if [ "$FIRST" = true ]; then FIRST=false; else JSON+=','; fi
        JSON+="{\"cluster\":\"$cluster\",\"dimension\":\"$NAME\",\"score\":$VALUE}"
      done
    fi
  done
  JSON+=']'
  echo "$JSON" > "$DATA_FILE"
  TIMESTAMP=$(date +%H:%M:%S)
  echo "[$TIMESTAMP] Updated scores"
  sleep 10
done
