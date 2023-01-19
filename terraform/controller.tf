resource "random_string" "controller" {
  count  = var.controller_count
  length = 4

  numeric = true
  lower   = true
  upper   = false
  special = false
}

resource "hcloud_server" "controller" {
  count       = var.controller_count
  name        = "controller-${resource.random_string.controller[count.index].result}"
  server_type = "cx11"
  location    = "fsn1"
  image       = "rocky-9"

  ssh_keys  = [hcloud_ssh_key.mhnet.id]
  user_data = local.userdata

  public_net {
    ipv4_enabled = true
    ipv6_enabled = true
  }
  firewall_ids = [hcloud_firewall.default.id]
  network {
    network_id = hcloud_network.internal.id
  }

  labels = merge(var.default_labels, {
    "role" = "controller"
  })

  depends_on = [
    hcloud_network_subnet.internal
  ]

  lifecycle {
    replace_triggered_by = [
      random_string.controller[count.index].result
    ]
  }
}
