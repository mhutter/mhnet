apply: kustomize helmfile

kustomize:
	kubectl apply -k .

helmfile:
	helmfile apply --skip-diff-on-install
