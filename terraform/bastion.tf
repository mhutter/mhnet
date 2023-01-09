resource "hcloud_firewall" "bastion" {
  name = "bastion"

  rule {
    direction = "in"
    protocol  = "icmp"
    source_ips = [
      "0.0.0.0/0",
      "::/0",
    ]
  }

  labels = var.default_labels
}

resource "hcloud_server" "bastion" {
  name        = "bastion.${var.domain}"
  server_type = "cx11"
  location    = "fsn1"
  image       = "rocky-9"

  ssh_keys  = [hcloud_ssh_key.mhnet.id]
  user_data = local.userdata

  public_net {
    ipv4_enabled = false
    ipv6_enabled = true
  }
  firewall_ids = [hcloud_firewall.bastion.id]
  network {
    network_id = hcloud_network.internal.id
  }

  labels = merge(var.default_labels, {
    "role" = "bastion"
  })

  depends_on = [
    hcloud_network_subnet.internal
  ]
}
