terraform {
  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "1.38.1"
    }
  }
}

provider "hcloud" {}
