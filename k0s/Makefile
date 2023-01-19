K0S_VERSION := "1.25.4+k0s.0"

.PHONY: k0sctl.yaml
k0sctl.yaml:
	hcloud server list -o json \
		| jsonnet \
			--tla-str sshUser="$(SSH_USER)" \
			--tla-code sshPort="$(SSH_PORT)" \
			--tla-str k0sVersion="$(K0S_VERSION)" \
			-- k0s.jsonnet \
		| yq --output-format yaml --prettyPrint \
		> "$@"

.PHONY: kubeconfig
kubeconfig:
	k0sctl kubeconfig > "$@"


.PHONY: apply
apply:
	k0sctl apply --kubeconfig-out kubeconfig

.PHONY: reset
reset:
	k0sctl reset
