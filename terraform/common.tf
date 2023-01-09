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

# resource "hcloud_load_balancer" "ingress" {
#   name               = "ingress"
#   load_balancer_type = "lb11"
#   location           = "fsn1"
#   algorithm {
#     type = "round_robin"
#   }

#   labels = var.default_labels
# }

# resource "hcloud_load_balancer_network" "ingress" {
#   load_balancer_id = hcloud_load_balancer.ingress.id
#   subnet_id        = hcloud_network_subnet.internal.id

# }

# resource "hcloud_load_balancer_service" "ingress-80" {
#   load_balancer_id = hcloud_load_balancer.ingress.id
#   protocol         = "http"
#   proxyprotocol    = true
# }
# resource "hcloud_load_balancer_service" "ingress-443" {
#   load_balancer_id = hcloud_load_balancer.ingress.id
#   protocol         = "tcp"
#   listen_port      = 443
#   destination_port = 443
#   proxyprotocol    = true
# }

# resource "hcloud_load_balancer_target" "name" {
#   load_balancer_id = hcloud_load_balancer.ingress.id
#   type             = "label_selector"
#   label_selector   = "mhnet.dev/role=worker"
#   use_private_ip   = true
#   depends_on = [
#     hcloud_load_balancer_network.ingress
#   ]
# }
