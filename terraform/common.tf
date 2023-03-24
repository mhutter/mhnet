locals {
  userdata = templatefile("userdata.yml", {
    ssh_key  = var.ssh_key,
    ssh_port = var.ssh_port,
    ssh_user = var.ssh_user,
  })
}

resource "hcloud_ssh_key" "mhnet" {
  name       = "mhnet"
  public_key = var.ssh_key
  labels     = var.default_labels
}

resource "hcloud_network" "internal" {
  name     = "internal"
  ip_range = var.ip_range

  labels = var.default_labels
}

resource "hcloud_network_subnet" "internal" {
  network_id   = hcloud_network.internal.id
  type         = "cloud"
  ip_range     = var.ip_range
  network_zone = "eu-central"
}

resource "hcloud_firewall" "default" {
  name = "default"

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
