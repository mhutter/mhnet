variable "default_labels" {
  type = map(string)
  default = {
    "managed-by" = "terraform"
    "source"     = "github.com-mhutter-mhnet"
  }
}

variable "ssh_port" {
  type = number
}

variable "ssh_user" {
  type = string
}

variable "ssh_key" {
  type    = string
  default = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILRFlkyW0MXxYjA1HUzJ18nlTLtXOHKV0rVJD/46v7Sb tera2023"
}

variable "ip_range" {
  type    = string
  default = "10.42.0.0/24"
}

variable "ip_offsets" {
  type = map(number)
  default = {
    "bastion" = 10
    "ares"    = 20
  }
}
