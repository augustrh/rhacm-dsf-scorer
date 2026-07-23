#!/bin/bash
# Step 3+4: Deploy scorer to managed clusters via ManifestWork
# Discovers apps domains, applies manifests, generates tokens, re-applies.
# Usage: bash scripts/03-deploy-scorer.sh [cluster1 cluster2 ...]
# Default: dsf-1 dsf-2 dsf-apac

set -euo pipefail

CLUSTERS="${@:-dsf-1 dsf-2 dsf-apac}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MANIFESTS_DIR="$SCRIPT_DIR/../manifests"

# Region map (compatible with macOS bash 3.2)
get_region() {
  case "$1" in
    dsf-1)    echo "us-east-1" ;;
    dsf-2)    echo "us-west-2" ;;
    dsf-apac) echo "ap-northeast-1" ;;
    *)        echo "unknown" ;;
  esac
}

echo "=== Step 3+4: Deploy Scorer ==="

for cluster in $CLUSTERS; do
  echo ""
  echo "--- $cluster ---"

  KUBECONFIG_FILE="/tmp/${cluster}-kubeconfig.yaml"
  MANIFEST="$MANIFESTS_DIR/manifestwork-${cluster}.yaml"
  TEMPLATE="$MANIFESTS_DIR/manifestwork.yaml.example"
  REGION=$(get_region "$cluster")

  # Check kubeconfig exists
  if [ ! -f "$KUBECONFIG_FILE" ]; then
    echo "ERROR: $KUBECONFIG_FILE not found. Run: bash scripts/extract-kubeconfigs.sh"
    continue
  fi

  # Get apps domain from managed cluster
  echo "Getting apps domain..."
  APPS_DOMAIN=$(KUBECONFIG="$KUBECONFIG_FILE" \
    oc get ingress.config.openshift.io cluster -o jsonpath='{.spec.domain}' 2>/dev/null)

  if [ -z "$APPS_DOMAIN" ]; then
    echo "ERROR: Could not get apps domain for $cluster"
    continue
  fi
  echo "Apps domain: $APPS_DOMAIN"

  # Generate manifest from template if it doesn't exist, or update existing
  if [ ! -f "$MANIFEST" ]; then
    echo "Creating $MANIFEST from template..."
    cp "$TEMPLATE" "$MANIFEST"
  fi

  # Set cluster-specific values
  sed -i.bak "s|namespace: <YOUR_MANAGED_CLUSTER_NAME>|namespace: ${cluster}|g" "$MANIFEST"
  sed -i.bak "s|namespace: ${cluster}|namespace: ${cluster}|g" "$MANIFEST"  # idempotent
  sed -i.bak "s|value: \"<YOUR_CLUSTER_REGION>\"|value: \"${REGION}\"|g" "$MANIFEST"
  # APPS_DOMAIN already includes "apps." prefix, so replace the whole "apps.<placeholder>" pattern
  sed -i.bak "s|apps.<YOUR_CLUSTER_DOMAIN>|${APPS_DOMAIN}|g" "$MANIFEST"
  sed -i.bak "s|apps.<DSF[^>]*_APPS_DOMAIN>|${APPS_DOMAIN}|g" "$MANIFEST"
  rm -f "$MANIFEST.bak"

  # First apply — creates SA, service, route (token placeholder is fine)
  echo "Applying ManifestWork (first pass — creates SA)..."
  oc apply -f "$MANIFEST"

  # Wait for SA to be created on managed cluster
  echo "Waiting for ServiceAccount on managed cluster..."
  for i in $(seq 1 30); do
    if KUBECONFIG="$KUBECONFIG_FILE" oc get sa rhacm-scorer -n dynamic-scoring &>/dev/null; then
      echo "ServiceAccount ready."
      break
    fi
    sleep 2
  done

  # Generate token
  echo "Generating Prometheus token..."
  TOKEN=$(KUBECONFIG="$KUBECONFIG_FILE" \
    oc create token rhacm-scorer -n dynamic-scoring --duration=8760h 2>/dev/null || true)

  if [ -z "$TOKEN" ]; then
    echo "WARNING: Could not generate token. SA may not be ready yet."
    echo "  Re-run this script after the ManifestWork propagates."
    continue
  fi

  # Update manifest with token and re-apply
  sed -i.bak "s|token: <YOUR_PROMETHEUS_SERVICE_ACCOUNT_TOKEN>|token: ${TOKEN}|g" "$MANIFEST"
  sed -i.bak "s|token: <DSF[^>]*_PROMETHEUS_TOKEN>|token: ${TOKEN}|g" "$MANIFEST"
  rm -f "$MANIFEST.bak"

  echo "Re-applying ManifestWork with token..."
  oc apply -f "$MANIFEST"

  echo "[$cluster] Done — region: $REGION, domain: $APPS_DOMAIN"
done

echo ""
echo "=== Scorer deployment complete ==="
echo "REMINDER: Do not commit the manifestwork-*.yaml files with tokens to git."
