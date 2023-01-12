#!/usr/bin/env bash
set -e -u -o pipefail

hcloud server list -o json | \
  jq \
    --arg ssh_user "$SSH_USER" \
    --argjson ssh_port "$SSH_PORT" \
    --arg k0s_version "1.25.4+k0s.0" \
    '[.[]
    | select(any(
        .labels.role; contains(["worker", "controller"][])
      ))
    | {
      role: .labels.role,
      privateInterface: "ens10",
      privateAddress: .private_net[0].ip,
      ssh: {
        address: .private_net[0].ip,
        port: $ssh_port,
        user: $ssh_user,
      }
    }] as $hosts
    | .[] | select(.labels.role == "controller").private_net[0].ip as $api_host
    | {
      apiVersion: "k0sctl.k0sproject.io/v1beta1",
      kind: "Cluster",
      metadata: { name: "k0s-cluster" },
      spec: {
        hosts: $hosts,
        k0s: {
          version: $k0s_version,
          dynamicConfig: false,
          config: {
            apiVersion: "k0sctl.k0sproject.io/v1beta1",
            kind: "Cluster",
            metadata: { name: "k0s-cluster" },
            spec: {
              network: {
                podCIDR: "10.244.0.0/16",
                serviceCIDR: "10.96.0.0/12",
                provider: "custom",
                kubeProxy: { disabled: true },
              },
              telemetry: { enabled: false },
              extensions: {
                helm: {
                  repositories: [{
                    name: "cilium",
                    url: "https://helm.cilium.io/",
                  }],
                  charts: [{
                    name: "cilium",
                    chartname: "cilium/cilium",
                    namespace: "kube-system",
                    values: ({
                      kubeProxyReplacement: "strict",
                      k8sServiceHost: $api_host,
                      k8sServicePort: 6443,
                    } | @json),
                  }],
                },
              },
            },
          },
        },
      },
    }' | yq --output-format yaml --prettyPrint
