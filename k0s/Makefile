.PHONY: k0sctl.yaml
k0sctl.yaml:
	./generate-config.sh > "$@"

.PHONY: kubeconfig
kubeconfig:
	k0sctl kubeconfig > "$@"


.PHONY: apply
apply:
	k0sctl apply --no-wait

.PHONY: reset
reset:
	k0sctl reset
