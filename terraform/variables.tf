variable "default_labels" {
  type = map(string)
  default = {
    "managed-by" = "terraform"
    "source"     = "github.com-mhutter-mhnet"
  }
}

variable "domain" {
  type    = string
  default = "mhnet.dev"
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

variable "worker_count" {
  type    = number
  default = 3
}
