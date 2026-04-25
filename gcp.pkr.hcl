packer {
  required_plugins {
    googlecompute = {
      version = ">= 1.2.5"
      source  = "github.com/hashicorp/googlecompute"
    }
  }
}

variable "go_version" {
  type        = string
  description = "Go release to install"
  default     = "1.26.2"
}

source "googlecompute" "ubuntu" {
  project_id = "quic-perf-dashboard"
  zone       = "us-west1-b"

  source_image_family = "ubuntu-2404-lts-amd64"
  image_family        = "quic-perf-runner"

  machine_type = "e2-medium"
  disk_size    = 20 # GB

  ssh_username = "packer"
  communicator = "ssh"

  tags = ["packer"]
}

build {
  sources = ["source.googlecompute.ubuntu"]

  provisioner "shell" {
    inline = [
      "echo '=== Updating package list and installing git ==='",
      "sudo apt-get update && sudo apt-get install -y git",

      "echo '=== Cloning quic-go source code to /opt/quic-go ==='",
      "sudo git clone https://github.com/quic-go/quic-go.git /opt/quic-go",
    ]
  }

  # Install Go into /usr/local/go
  provisioner "shell" {
    inline = [
      "set -eux",
      "echo '=== Installing Go ${var.go_version} ==='",
      "curl -fsSL 'https://go.dev/dl/go${var.go_version}.linux-amd64.tar.gz' -o /tmp/go.tar.gz",
      "sudo tar -C /usr/local -xzf /tmp/go.tar.gz",
      "rm /tmp/go.tar.gz",
      "sudo ln -sf /usr/local/go/bin/go /usr/local/bin/go",
    ]
  }
}
