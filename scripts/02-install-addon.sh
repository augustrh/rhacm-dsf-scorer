#!/bin/bash
# Step 2: Install the DSF addon on the hub and patch for RHACM
# Usage: bash scripts/02-install-addon.sh

set -euo pipefail

echo "=== Step 2: Install DSF Addon ==="

# Add Helm repo
helm repo add ocm https://open-cluster-management-io.github.io/helm-charts 2>/dev/null || true
helm repo update

# Install (or upgrade if already installed)
if helm status dynamic-scoring-framework -n open-cluster-management &>/dev/null; then
  echo "DSF addon already installed, upgrading..."
  helm upgrade dynamic-scoring-framework ocm/dynamic-scoring-framework \
    -n open-cluster-management
else
  echo "Installing DSF addon..."
  helm install dynamic-scoring-framework ocm/dynamic-scoring-framework \
    -n open-cluster-management --create-namespace
fi

# Patch for RHACM global placement
echo ""
echo "Patching ClusterManagementAddOn for RHACM global placement..."
oc patch clustermanagementaddon dynamic-scoring \
  -n open-cluster-management --type merge \
  -p '{"spec":{"installStrategy":{"type":"Placements","placements":[{"name":"global","namespace":"open-cluster-management","rolloutStrategy":{"type":"All"}}]}}}'

echo ""
echo "Waiting for addon to deploy to managed clusters..."
echo "Run: oc get managedclusteraddon -A | grep dynamic-scoring"
echo ""
oc get managedclusteraddon -A | grep dynamic-scoring || true
