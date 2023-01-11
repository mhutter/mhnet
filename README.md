# mhnet Infrastructure


## Setup


Ensure the following environment variables are set (using `envrc` or the likes):

```sh
export HCLOUD_TOKEN=???
export SSH_PORT=???
export SSH_USER=???

export TF_VAR_ssh_port="$SSH_PORT"
export TF_VAR_ssh_user="$SSH_USER"
export KUBECONFIG="${PWD}/k0s/kubeconfig"
```
