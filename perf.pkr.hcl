packer {
  required_plugins {
    amazon = {
      version = ">= 1.3.9"
      source  = "github.com/hashicorp/amazon"
    }
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

source "amazon-ebs" "ubuntu" {
  region = "us-west-2"

  source_ami_filter {
    filters = {
      name                = "ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"
      root-device-type    = "ebs"
      virtualization-type = "hvm"
    }
    most_recent = true
    owners      = ["099720109477"]
  }

  ami_name        = "quic-perf-runner-{{timestamp}}"
  ami_description = "QUIC perf runner"
  instance_type   = "c6i.large"
  ssh_username    = "ubuntu"

  launch_block_device_mappings {
    device_name           = "/dev/sda1"
    volume_size           = 20
    volume_type           = "gp3"
    delete_on_termination = true
  }

  tags = {
    Name      = "quic-perf-runner"
    ManagedBy = "packer"
  }
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
  sources = [
    "source.amazon-ebs.ubuntu",
    "source.googlecompute.ubuntu",
  ]

  provisioner "shell" {
    environment_vars = ["DEBIAN_FRONTEND=noninteractive"]
    inline = [
      "echo '=== Updating package list and installing git ==='",
      "sudo apt-get update && sudo apt-get install -y git",

      "echo '=== Cloning quic-go source code to /opt/quic-go ==='",
      "sudo git clone https://github.com/quic-go/quic-go.git /opt/quic-go",
    ]
  }

  # Install Go into /usr/local/go
  provisioner "shell" {
    environment_vars = ["DEBIAN_FRONTEND=noninteractive"]
    inline = [
      "set -eux",
      "echo '=== Installing Go ${var.go_version} ==='",
      "curl -fsSL 'https://go.dev/dl/go${var.go_version}.linux-amd64.tar.gz' -o /tmp/go.tar.gz",
      "sudo tar -C /usr/local -xzf /tmp/go.tar.gz",
      "rm /tmp/go.tar.gz",
      "sudo ln -sf /usr/local/go/bin/go /usr/local/bin/go",
    ]
  }

  # Build MsQuic with the perf tool enabled.
  provisioner "shell" {
    environment_vars = ["DEBIAN_FRONTEND=noninteractive"]
    inline = [
      "set -eux",
      "echo '=== Installing MsQuic build dependencies ==='",
      "sudo apt-get install -y cmake build-essential g++",

      "echo '=== Cloning microsoft/msquic to /opt/msquic ==='",
      "sudo git clone --depth 1 --branch main --single-branch https://github.com/microsoft/msquic.git /opt/msquic",
      "sudo git -C /opt/msquic submodule update --init --recursive --depth 1",

      "echo '=== Building MsQuic with QUIC_BUILD_PERF=ON ==='",
      "sudo mkdir -p /opt/msquic/build",
      "cd /opt/msquic/build && sudo cmake -G 'Unix Makefiles' -DQUIC_BUILD_PERF=ON ..",
      "sudo make -C /opt/msquic/build",
    ]
  }

  # Stage the auto-shutdown files in /tmp; the SSH user can't write to
  # privileged paths directly, so the shell provisioner installs them.
  provisioner "file" {
    source      = "${path.root}/files/"
    destination = "/tmp/"
  }

  provisioner "shell" {
    inline = [
      "echo '=== Installing auto-shutdown service ==='",
      "sudo install -o root -g root -m 0755 /tmp/shutdown-check.sh      /usr/local/sbin/shutdown-check.sh",
      "sudo install -o root -g root -m 0644 /tmp/shutdown-check.service /etc/systemd/system/shutdown-check.service",
      "sudo install -o root -g root -m 0644 /tmp/shutdown-check.timer   /etc/systemd/system/shutdown-check.timer",
      "rm /tmp/shutdown-check.sh /tmp/shutdown-check.service /tmp/shutdown-check.timer",
      "sudo systemctl enable shutdown-check.timer",
    ]
  }
}
