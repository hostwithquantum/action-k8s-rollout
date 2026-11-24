#!/usr/bin/env bash
# Wait for the rollout of one or more workloads, all at the same time.
#
# Config (environment):
#   ROLLOUT_RESOURCES  list of kind/name (space, comma or newline separated),
#                      a bare name means deployment/name
#   ROLLOUT_SELECTOR   label selector, matches deployments, statefulsets, daemonsets
#   ROLLOUT_MANIFEST   manifest file, watches all workloads in it
#   ROLLOUT_NAMESPACE  namespace (default: from kube context or manifest)
#   ROLLOUT_TIMEOUT    timeout per resource (default: 5m)
set -euo pipefail

RESOURCES=${ROLLOUT_RESOURCES:-}
SELECTOR=${ROLLOUT_SELECTOR:-}
MANIFEST=${ROLLOUT_MANIFEST:-}
NAMESPACE=${ROLLOUT_NAMESPACE:-}
TIMEOUT=${ROLLOUT_TIMEOUT:-5m}

# a plain number is seconds
case $TIMEOUT in
  *[!0-9]*) ;;
  *) TIMEOUT="${TIMEOUT}s" ;;
esac

# prints one "kind/name namespace" line per workload to watch
targets() {
  tr -s ', \t' '\n' <<<"$RESOURCES" | while read -r item; do
    case $item in
      "") ;;
      */*) echo "$item $NAMESPACE" ;;
      *) echo "deployment/$item $NAMESPACE" ;;
    esac
  done

  if [ -n "$SELECTOR" ]; then
    kubectl get deployments,statefulsets,daemonsets \
      ${NAMESPACE:+"--namespace=$NAMESPACE"} -l "$SELECTOR" -o name |
      awk -v ns="$NAMESPACE" '{print $1, ns}'
  fi

  if [ -n "$MANIFEST" ]; then
    kubectl get -f "$MANIFEST" ${NAMESPACE:+"--namespace=$NAMESPACE"} --no-headers \
      -o custom-columns=KIND:.kind,NAMESPACE:.metadata.namespace,NAME:.metadata.name |
      awk '$1 ~ /^(Deployment|StatefulSet|DaemonSet)$/ {print tolower($1) "/" $3, $2}'
  fi
}

# prefixes each line, so parallel output stays readable
watch() {
  local ref=$1 ns=$2
  kubectl rollout status "$ref" ${ns:+"--namespace=$ns"} --timeout="$TIMEOUT" 2>&1 |
    while IFS= read -r line; do echo "[$ref] $line"; done
}

report() {
  echo "$1"
  echo "$1" >>"${GITHUB_STEP_SUMMARY:-/dev/null}"
}

# "set -e" is not inherited by $(...), so set it again
list=$(
  set -e
  targets | sort -u
)

if [ -z "$list" ]; then
  echo "::error::nothing to watch: set resources, selector or manifest"
  exit 1
fi

pids=()
while read -r ref ns; do
  watch "$ref" "$ns" &
  pids+=($!)
done <<<"$list"

failed=0
i=0
while read -r ref ns; do
  if wait "${pids[$i]}"; then
    report "✅ ${ns:+$ns/}$ref rolled out"
  else
    failed=1
    report "❌ ${ns:+$ns/}$ref failed (timeout: $TIMEOUT)"
    echo "::group::describe $ref"
    kubectl describe "$ref" ${ns:+"--namespace=$ns"} || true
    echo "::endgroup::"
  fi
  i=$((i + 1))
done <<<"$list"

exit $failed
