resource "random_string" "worker" {
  count  = var.worker_count
  length = 4

  numeric = true
  lower   = true
  upper   = false
  special = false
}

resource "hcloud_placement_group" "workers" {
  name   = "workers"
  type   = "spread"
  labels = var.default_labels
}

resource "hcloud_server" "worker" {
  count       = var.worker_count
  name        = "worker-${resource.random_string.worker[count.index].result}"
  server_type = "cx21"
  location    = "fsn1"
  image       = "rocky-9"

  ssh_keys  = [hcloud_ssh_key.mhnet.id]
  user_data = local.userdata

  placement_group_id = hcloud_placement_group.workers.id

  public_net {
    ipv4_enabled = true
    ipv6_enabled = true
  }
  firewall_ids = [hcloud_firewall.default.id]
  network {
    network_id = hcloud_network.internal.id
  }

  labels = merge(var.default_labels, {
    "role" = "worker"
  })

  depends_on = [
    hcloud_network_subnet.internal
  ]
}
