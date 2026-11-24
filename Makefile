.PHONY: test lint build run-dev

test:
	bats test

lint:
	shellcheck rollout.sh test/bin/kubectl
	actionlint

# nothing to build, this is a composite action
build:
	@bash -n rollout.sh

# runs against your current kube context, e.g.
#   make run-dev ROLLOUT_NAMESPACE=default ROLLOUT_RESOURCES="web worker"
run-dev:
	./rollout.sh
