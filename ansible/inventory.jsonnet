local mapServer(inventory, s) =
  local role = s.labels.role;
  local hostvars = {
    ansible_host: s.private_net[0].ip,
  };

  inventory {
    [role]+: [s.name],
    _meta+: {
      hostvars+: {
        [s.name]: hostvars,
      },
    },
  };

local buildInventory(servers, sshPort) =
  std.foldl(mapServer, servers, {}) {
    all: {
      vars: {
        ssh_port: sshPort,
        ansible_port: sshPort,
      },
    },
  };


local main(sshPort) =
  local servers = import '/dev/stdin';
  buildInventory(servers, sshPort);

main
