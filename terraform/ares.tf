resource "hcloud_firewall" "ares" {
  name = "ares"

  rule {
    direction = "in"
    protocol  = "icmp"
    source_ips = [
      "0.0.0.0/0",
      "::/0",
    ]
  }
  rule {
    direction = "in"
    protocol  = "tcp"
    port      = "80"
    source_ips = [
      "0.0.0.0/0",
      "::/0",
    ]
  }
  rule {
    direction = "in"
    protocol  = "tcp"
    port      = "443"
    source_ips = [
      "0.0.0.0/0",
      "::/0",
    ]
  }

  labels = var.default_labels
}

resource "random_string" "ares" {
  length = 4

  numeric = true
  lower   = true
  upper   = false
  special = false
}

resource "hcloud_server" "ares" {
  name        = "ares-${resource.random_string.ares.result}"
  server_type = "cx21"
  location    = "fsn1"
  image       = "rocky-9"

  ssh_keys  = [hcloud_ssh_key.mhnet.id]
  user_data = local.userdata

  public_net {
    ipv4_enabled = true
    ipv6_enabled = true
  }
  firewall_ids = [hcloud_firewall.ares.id]
  network {
    network_id = hcloud_network.internal.id
    ip         = cidrhost(var.ip_range, var.ip_offsets.ares)
  }

  labels = merge(var.default_labels, {
    "role" = "ares"
  })

  depends_on = [
    hcloud_network_subnet.internal
  ]

  lifecycle {
    replace_triggered_by = [
      random_string.ares.result
    ]
  }
}
