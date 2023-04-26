# mhnet Infrastructure


## Usage

_All command examples assume that they are run from the corresponding subdirectory._


### Terraform

Prepare a plan:

    make plan

Apply the plan:

    make apply


### Ansible

Just run `ansible` (or `ansible-playbook playbook.yml`) from the [`ansible/`](ansible/) directory.


### K0s cluster

Re-generate the `k0sctl.yaml` config file:

    make


Deploy the cluster & recreate the kubeconfig

    make apply
    make kubeconfig


### K0s single-node (ares)

Install & start K0s

    k0s install controller --single
    k0s start

Create kubeconfig & Clusterrolebinding

```sh
sudo k0s kubeconfig create "$USER" > kubeconfig
sudo k0s kubectl create clusterrolebinding "${USER}-admin" --clusterrole=cluster-admin --user="$USER"
```

### K8s manifests

    kubectl apply -k .
    helmfile apply


## Setup

Ensure the following environment variables are set (using `envrc` or the likes):

```sh
export HCLOUD_TOKEN=???
export SSH_PORT=???
export SSH_USER=???

export TF_VAR_ssh_port="$SSH_PORT"
export TF_VAR_ssh_user="$SSH_USER"
export KUBECONFIG="${PWD}/k0s/kubeconfig"
export SEALED_SECRETS_CONTROLLER_NAMESPACE=sealed-secrets
```
