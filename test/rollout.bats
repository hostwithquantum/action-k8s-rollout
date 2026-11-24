#!/usr/bin/env bats

setup() {
  export PATH="$BATS_TEST_DIRNAME/bin:$PATH"
  export KUBECTL_LOG="$BATS_TEST_TMPDIR/kubectl.log"
  touch "$KUBECTL_LOG"
  unset ROLLOUT_RESOURCES ROLLOUT_SELECTOR ROLLOUT_MANIFEST ROLLOUT_NAMESPACE ROLLOUT_TIMEOUT
  unset GITHUB_STEP_SUMMARY
}

rollout() {
  run "$BATS_TEST_DIRNAME/../rollout.sh"
}

@test "fails when there is nothing to watch" {
  rollout
  [ "$status" -eq 1 ]
  [[ "$output" == *"nothing to watch"* ]]
}

@test "bare name is a deployment, default timeout is 5m" {
  export ROLLOUT_RESOURCES=web ROLLOUT_NAMESPACE=prod
  rollout
  [ "$status" -eq 0 ]
  grep -qx "rollout status deployment/web --namespace=prod --timeout=5m" "$KUBECTL_LOG"
  [[ "$output" == *"✅ prod/deployment/web rolled out"* ]]
}

@test "accepts space, comma and newline separated lists" {
  export ROLLOUT_RESOURCES=$'web, worker\nstatefulset/db'
  rollout
  [ "$status" -eq 0 ]
  grep -qx "rollout status deployment/web --timeout=5m" "$KUBECTL_LOG"
  grep -qx "rollout status deployment/worker --timeout=5m" "$KUBECTL_LOG"
  grep -qx "rollout status statefulset/db --timeout=5m" "$KUBECTL_LOG"
}

@test "plain number timeout is seconds" {
  export ROLLOUT_RESOURCES=web ROLLOUT_TIMEOUT=90
  rollout
  grep -q -- "--timeout=90s" "$KUBECTL_LOG"
}

@test "fails and describes when one rollout fails" {
  export ROLLOUT_RESOURCES="web worker" STUB_FAIL=deployment/worker
  rollout
  [ "$status" -eq 1 ]
  [[ "$output" == *"✅ deployment/web rolled out"* ]]
  [[ "$output" == *"❌ deployment/worker failed"* ]]
  [[ "$output" == *"described deployment/worker"* ]]
  ! grep -q "describe deployment/web" "$KUBECTL_LOG"
}

@test "selector watches all matches" {
  export ROLLOUT_SELECTOR=heritage=runway ROLLOUT_NAMESPACE=prod
  export STUB_GET=$'deployment.apps/web\ndaemonset.apps/agent\n'
  rollout
  [ "$status" -eq 0 ]
  grep -q "get deployments,statefulsets,daemonsets --namespace=prod -l heritage=runway" "$KUBECTL_LOG"
  grep -qx "rollout status deployment.apps/web --namespace=prod --timeout=5m" "$KUBECTL_LOG"
  grep -qx "rollout status daemonset.apps/agent --namespace=prod --timeout=5m" "$KUBECTL_LOG"
}

@test "manifest watches workloads only, with their namespace" {
  export ROLLOUT_MANIFEST=all.yml
  export STUB_GET=$'Service a web\nDeployment a web\nCronJob a cleanup\nStatefulSet b db\nClusterRole <none> x\n'
  rollout
  [ "$status" -eq 0 ]
  grep -qx "rollout status deployment/web --namespace=a --timeout=5m" "$KUBECTL_LOG"
  grep -qx "rollout status statefulset/db --namespace=b --timeout=5m" "$KUBECTL_LOG"
  [ "$(grep -c "^rollout status" "$KUBECTL_LOG")" -eq 2 ]
}

@test "fails when the lookup fails" {
  export ROLLOUT_MANIFEST=missing.yml STUB_GET_EXIT=1
  rollout
  [ "$status" -ne 0 ]
  ! grep -q "^rollout status" "$KUBECTL_LOG"
}

@test "watches in parallel" {
  export ROLLOUT_RESOURCES="a b c d" STUB_SLEEP=2
  SECONDS=0
  rollout
  [ "$status" -eq 0 ]
  [ "$SECONDS" -lt 6 ]
}

@test "writes the step summary" {
  export ROLLOUT_RESOURCES=web GITHUB_STEP_SUMMARY="$BATS_TEST_TMPDIR/summary"
  rollout
  grep -q "✅ deployment/web rolled out" "$GITHUB_STEP_SUMMARY"
}
