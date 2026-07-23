#!/bin/bash
# Shared helpers — sourced by all DSF scorer scripts.
# Reads cluster config from clusters.conf at the repo root.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CONF_FILE="${CONF_FILE:-$REPO_ROOT/clusters.conf}"

_CLUSTER_NAMES=()
_CLUSTER_REGIONS=()
_CLUSTER_BIASES=()
_LOADED=false

_load() {
  $_LOADED && return
  if [ ! -f "$CONF_FILE" ]; then
    echo "ERROR: $CONF_FILE not found" >&2
    exit 1
  fi
  while IFS=: read -r name region bias; do
    [ -z "$name" ] && continue
    [[ "$name" == \#* ]] && continue
    _CLUSTER_NAMES+=("$name")
    _CLUSTER_REGIONS+=("$region")
    _CLUSTER_BIASES+=("${bias:-0}")
  done < "$CONF_FILE"
  if [ ${#_CLUSTER_NAMES[@]} -eq 0 ]; then
    echo "ERROR: No clusters defined in $CONF_FILE" >&2
    exit 1
  fi
  _LOADED=true
}

cluster_names() {
  _load
  echo "${_CLUSTER_NAMES[@]}"
}

get_region() {
  _load
  local target="$1"
  for i in "${!_CLUSTER_NAMES[@]}"; do
    if [ "${_CLUSTER_NAMES[$i]}" = "$target" ]; then
      echo "${_CLUSTER_REGIONS[$i]}"
      return
    fi
  done
  echo "unknown"
}

get_bias() {
  _load
  local target="$1"
  for i in "${!_CLUSTER_NAMES[@]}"; do
    if [ "${_CLUSTER_NAMES[$i]}" = "$target" ]; then
      echo "${_CLUSTER_BIASES[$i]}"
      return
    fi
  done
  echo "0"
}

build_region_bias_json() {
  _load
  local json="{"
  local first=true
  for i in "${!_CLUSTER_NAMES[@]}"; do
    local region="${_CLUSTER_REGIONS[$i]}"
    local bias="${_CLUSTER_BIASES[$i]}"
    if $first; then first=false; else json+=", "; fi
    json+="\"$region\": $bias"
  done
  json+="}"
  echo "$json"
}

first_cluster() {
  _load
  echo "${_CLUSTER_NAMES[0]}"
}
