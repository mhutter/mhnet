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
  ip_range = "10.42.0.0/16"

  labels = var.default_labels
}

resource "hcloud_network_subnet" "internal" {
  network_id   = hcloud_network.internal.id
  type         = "cloud"
  ip_range     = "10.42.0.0/24"
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

resource "hcloud_load_balancer" "ingress" {
  name               = "ingress"
  load_balancer_type = "lb11"
  location           = "fsn1"
  algorithm {
    type = "round_robin"
  }

  labels = var.default_labels
}

resource "hcloud_load_balancer_network" "ingress" {
  load_balancer_id = hcloud_load_balancer.ingress.id
  subnet_id        = hcloud_network_subnet.internal.id
}

resource "hcloud_load_balancer_service" "ingress-80" {
  load_balancer_id = hcloud_load_balancer.ingress.id
  protocol         = "http"
  destination_port = 30080

  health_check {
    protocol = "http"
    port     = 30080
    http {
      path         = "/healthz"
      status_codes = ["200"]
    }
    interval = 15
    timeout  = 10
    retries  = 3
  }
}

resource "hcloud_load_balancer_service" "ingress-443" {
  load_balancer_id = hcloud_load_balancer.ingress.id
  protocol         = "tcp"
  listen_port      = 443
  destination_port = 30443
}

resource "hcloud_load_balancer_target" "workers" {
  load_balancer_id = hcloud_load_balancer.ingress.id
  type             = "label_selector"
  label_selector   = "role=worker"
  use_private_ip   = true
  depends_on = [
    hcloud_load_balancer_network.ingress
  ]
}
