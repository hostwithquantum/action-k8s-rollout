# action-k8s-rollout

Wait for Kubernetes rollouts to finish. Watches many resources at the same time.

Needs `kubectl` and a working kube config on the runner.

## Usage

```yaml
- uses: hostwithquantum/action-k8s-rollout@main
  with:
    namespace: my-app
    resources: |
      some-service
      worker
      statefulset/db
```

Or watch every workload in the manifest you just applied:

```yaml
- run: kustomize build -o rollout.yml . && kubectl apply -f rollout.yml
- uses: hostwithquantum/action-k8s-rollout@main
  with:
    manifest: rollout.yml
    timeout: 10m
```

## Inputs

| name | default | description |
|------|---------|-------------|
| `resources` | | list of `kind/name` (space, comma or newline separated). A bare name means `deployment/name`. |
| `selector` | | label selector. Matches deployments, statefulsets and daemonsets. |
| `manifest` | | manifest file. Watches all deployments, statefulsets and daemonsets in it. |
| `namespace` | | namespace. Default is from the kube context or the manifest. |
| `timeout` | `5m` | timeout per resource. A plain number is seconds. |

Set at least one of `resources`, `selector` or `manifest`. They can be combined.

The step fails when one rollout fails or times out. Failed resources are
described in the log, and the result is added to the step summary.

## Development

```sh
make test   # needs bats
make lint   # needs shellcheck and actionlint
make run-dev ROLLOUT_NAMESPACE=default ROLLOUT_RESOURCES="web worker"
```
