local k0sConfig(apiHost) =
  {
    apiVersion: 'k0s.k0sproject.io/v1beta1',
    kind: 'Cluster',
    metadata: { name: 'k0s-cluster' },
    spec: {
      network: {
        podCIDR: '10.244.0.0/16',
        serviceCIDR: '10.96.0.0/12',
        provider: 'custom',
        kubeProxy: { disabled: true },
      },
      telemetry: { enabled: false },
      extensions: {
        helm: {
          repositories: [{
            name: 'cilium',
            url: 'https://helm.cilium.io/',
          }],
          charts: [{
            name: 'cilium',
            chartname: 'cilium/cilium',
            namespace: 'kube-system',
            values: std.manifestJsonMinified({
              kubeProxyReplacement: 'strict',
              k8sServiceHost: apiHost,
              k8sServicePort: 6443,
            }),
          }],
        },
      },
    },
  };

local k0sctlConfig(apiHost, k0sVersion, hosts) =
  {
    apiVersion: 'k0sctl.k0sproject.io/v1beta1',
    kind: 'Cluster',
    metadata: { name: 'k0s-cluster' },
    spec: {
      hosts: hosts,
      k0s: {
        version: k0sVersion,
        dynamicConfig: false,
        config: k0sConfig(apiHost),
      },
    },
  };

local renderHost(sshPort, sshUser) = function(s)
  local isController = s.labels.role == 'controller';
  {
    role: if isController then 'controller+worker' else 'worker',
    [if isController then 'installFlags']: ['--enable-metrics-scraper'],
    privateInterface: 'ens10',
    privateAddress: s.private_net[0].ip,
    ssh: {
      address: s.private_net[0].ip,
      port: sshPort,
      user: sshUser,
    },
  };

local k0sHosts(sshPort, sshUser, servers) =
  std.filterMap(
    function(s) std.member(['controller', 'worker'], s.labels.role),
    renderHost(sshPort, sshUser),
    servers
  );


local main(sshPort, sshUser, k0sVersion) =
  local servers = import '/dev/stdin';
  local hosts = k0sHosts(sshPort, sshUser, servers);
  local apiHost = std.filterMap(
    function(s) s.role == 'controller+worker',
    function(h) h.privateAddress,
    hosts
  )[0];

  k0sctlConfig(apiHost, k0sVersion, hosts);

main
