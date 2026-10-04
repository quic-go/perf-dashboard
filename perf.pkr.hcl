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
    azure = {
      version = ">= 2.6.1"
      source  = "github.com/hashicorp/azure"
    }
    docker = {
      version = ">= 1.1.4"
      source  = "github.com/hashicorp/docker"
    }
  }
}

variable "go_version" {
  type        = string
  description = "Go release to install"
  default     = "1.26.2"
}

variable "architecture" {
  type        = string
  description = "Runner CPU architecture"
  default     = "amd64"

  validation {
    condition     = contains(["amd64", "arm64"], var.architecture)
    error_message = "Architecture must be amd64 or arm64."
  }
}

variable "build_commit" {
  type        = string
  description = "perf-dashboard commit used to build the image"
}

variable "gcp_project_id" {
  type        = string
  description = "GCP project ID"
  default     = ""
}

variable "azure_resource_group" {
  type        = string
  description = "Azure resource group"
  default     = ""
}

variable "ssh_public_key_primary" {
  type        = string
  description = "SSH public key required for CI access to runner images"

  validation {
    condition     = var.ssh_public_key_primary != ""
    error_message = "Primary SSH public key must be set."
  }
}

variable "ssh_public_keys_additional" {
  type        = list(string)
  description = "Additional SSH public keys authorized for debugging runner images"
  default     = []
}

locals {
  image_name   = "quic-perf-runner-${var.architecture}-${formatdate("YYYYMMDDhhmmss", timestamp())}"
  image_family = "quic-perf-runner-${var.architecture}"
}

# The Docker image is only used for local development.
source "docker" "ubuntu" {
  image    = "ubuntu:24.04"
  platform = "linux/${var.architecture}"
  commit   = true

  changes = [
    "CMD [\"/usr/sbin/sshd\", \"-D\", \"-e\"]",
    "EXPOSE 22/tcp",
    "EXPOSE 4433/udp",
  ]
}

source "amazon-ebs" "ubuntu" {
  region = "us-west-2"

  source_ami_filter {
    filters = {
      name                = "ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-${var.architecture}-server-*"
      root-device-type    = "ebs"
      virtualization-type = "hvm"
    }
    most_recent = true
    owners      = ["099720109477"]
  }

  ami_name        = local.image_name
  ami_description = "QUIC perf runner"
  instance_type   = var.architecture == "arm64" ? "c7g.large" : "c6i.large"
  ssh_username    = "ubuntu"

  launch_block_device_mappings {
    device_name           = "/dev/sda1"
    volume_size           = 20
    volume_type           = "gp3"
    delete_on_termination = true
  }

  tags = {
    Name      = local.image_family
    ManagedBy = "packer"
  }
}

source "googlecompute" "ubuntu" {
  project_id = var.gcp_project_id
  zone       = var.architecture == "arm64" ? "us-central1-a" : "us-west1-b"

  source_image_family = "ubuntu-2404-lts-${var.architecture}"
  image_name          = local.image_name
  image_family        = local.image_family

  machine_type = var.architecture == "arm64" ? "t2a-standard-2" : "e2-medium"
  disk_size    = 20 # GB

  ssh_username = "packer"
  communicator = "ssh"

  disable_default_service_account = true

  tags = ["packer"]
}

source "azure-arm" "ubuntu" {
  use_azure_cli_auth = true

  build_resource_group_name = var.azure_resource_group

  shared_image_gallery_destination {
    resource_group = var.azure_resource_group
    gallery_name   = "quicperfrunner"
    image_name     = local.image_family
    image_version  = format("%s.%d.0", formatdate("YYYYMMDD", timestamp()), formatdate("hhmmss", timestamp()))
  }
  shared_gallery_image_version_exclude_from_latest = true

  os_type         = "Linux"
  image_publisher = "Canonical"
  image_offer     = "ubuntu-24_04-lts"
  image_sku       = var.architecture == "arm64" ? "server-arm64" : "server"
  image_version   = "latest"

  vm_size         = var.architecture == "arm64" ? "Standard_D2ps_v5" : "Standard_D2s_v5"
  os_disk_size_gb = 30

  # Azure builds use an existing resource group, so tag leftovers for cleanup.
  # The workflow retains and publishes the gallery version after a successful build.
  azure_tags = {
    ManagedBy       = "packer"
    PackerLifecycle = "temporary"
  }
}

build {
  sources = [
    "source.amazon-ebs.ubuntu",
    "source.googlecompute.ubuntu",
    "source.azure-arm.ubuntu",
    "source.docker.ubuntu",
  ]

  provisioner "shell" {
    only             = ["docker.ubuntu"]
    environment_vars = ["DEBIAN_FRONTEND=noninteractive"]
    inline = [
      "apt-get update && apt-get install -y openssh-server sudo",
      "mkdir -p /run/sshd",
    ]
  }

  provisioner "shell" {
    environment_vars = ["DEBIAN_FRONTEND=noninteractive"]
    inline = [
      "echo '=== Updating package list and installing base packages ==='",
      "sudo apt-get update && sudo apt-get install -y ca-certificates curl git jq zstd",
    ]
  }

  provisioner "shell" {
    environment_vars = [
      "AUTHORIZED_SSH_PUBLIC_KEYS=${join("\n", concat([var.ssh_public_key_primary], var.ssh_public_keys_additional))}",
    ]
    inline = [
      "set -eux",
      "echo '=== Creating perf SSH user ==='",
      "sudo useradd --create-home --shell /bin/bash perf",
      "sudo install -d -o perf -g perf -m 0700 /home/perf/.ssh",
      "printf '%s\n' \"$${AUTHORIZED_SSH_PUBLIC_KEYS}\" | sudo tee /home/perf/.ssh/authorized_keys >/dev/null",
      "sudo chown perf:perf /home/perf/.ssh/authorized_keys",
      "sudo chmod 0600 /home/perf/.ssh/authorized_keys",
    ]
  }

  # Install Go into /usr/local/go
  provisioner "shell" {
    environment_vars = ["DEBIAN_FRONTEND=noninteractive"]
    inline = [
      "set -eux",
      "echo '=== Installing Go ${var.go_version} ==='",
      "curl -fsSL 'https://go.dev/dl/go${var.go_version}.linux-${var.architecture}.tar.gz' -o /tmp/go.tar.gz",
      "sudo tar -C /usr/local -xzf /tmp/go.tar.gz",
      "rm /tmp/go.tar.gz",
      "sudo ln -sf /usr/local/go/bin/go /usr/local/bin/go",
    ]
  }

  # Build quic-go/perf against a local quic-go checkout using a Go workspace.
  provisioner "shell" {
    inline = [
      "set -eux",
      "echo '=== Cloning quic-go sources to /opt/quic-go ==='",
      "sudo install -d -o root -g root -m 0755 /opt/quic-go",
      "sudo git clone --depth 1 https://github.com/quic-go/perf.git /opt/quic-go/perf",
      "sudo git clone --depth 1 https://github.com/quic-go/quic-go.git /opt/quic-go/quic-go",

      "echo '=== Creating Go workspace for quic-go/perf ==='",
      "cd /opt/quic-go",
      "sudo go work init ./perf ./quic-go",

      "echo '=== Building quic-go-perf ==='",
      "sudo go build -o /opt/quic-go/perf/quic-go-perf ./perf/cmd",
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

  provisioner "shell" {
    environment_vars = ["BUILD_COMMIT=${var.build_commit}"]
    inline = [<<-EOF
      jq -n \
        --arg built_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        --arg build_commit "$BUILD_COMMIT" \
        --arg architecture "${var.architecture}" \
        --arg perf_commit "$(sudo git -C /opt/quic-go/perf rev-parse HEAD)" \
        --arg quic_go_commit "$(sudo git -C /opt/quic-go/quic-go rev-parse HEAD)" \
        --arg msquic_commit "$(sudo git -C /opt/msquic rev-parse HEAD)" \
        --arg go_version "$(go version /opt/quic-go/perf/quic-go-perf | awk '{print $NF}')" \
        --arg cxx_version "$(c++ -dumpfullversion -dumpversion)" \
        '{
          schema_version: 1,
          built_at: $built_at,
          perf_dashboard_commit: $build_commit,
          architecture: $architecture,
          implementations: {
            "quic-go": {commit: $quic_go_commit, perf_commit: $perf_commit, go_version: $go_version},
            "msquic": {commit: $msquic_commit, cxx_version: $cxx_version}
          }
        }' | sudo tee /home/perf/build-info.json >/dev/null
    EOF
    ]
  }

  # Stage the auto-shutdown files in /tmp; the SSH user can't write to
  # privileged paths directly, so the shell provisioner installs them.
  provisioner "file" {
    except      = ["docker.ubuntu"]
    source      = "${path.root}/files/"
    destination = "/tmp/"
  }

  provisioner "shell" {
    except = ["docker.ubuntu"]
    inline = [
      "echo '=== Installing auto-shutdown service ==='",
      "sudo install -o root -g root -m 0755 /tmp/shutdown-check.sh      /usr/local/sbin/shutdown-check.sh",
      "sudo install -o root -g root -m 0644 /tmp/shutdown-check.service /etc/systemd/system/shutdown-check.service",
      "sudo install -o root -g root -m 0644 /tmp/shutdown-check.timer   /etc/systemd/system/shutdown-check.timer",
      "rm /tmp/shutdown-check.sh /tmp/shutdown-check.service /tmp/shutdown-check.timer",
      "sudo systemctl enable shutdown-check.timer",
    ]
  }

  provisioner "shell" {
    only = ["azure-arm.ubuntu"]
    inline = [
      "echo '=== Deprovisioning Azure VM ==='",
      "sudo waagent -force -deprovision+user",
      "sync",
    ]
  }

  provisioner "shell" {
    only   = ["docker.ubuntu"]
    inline = ["/usr/sbin/sshd -t"]
  }

  post-processor "manifest" {
    output = "packer-manifest.json"
  }

  post-processor "docker-tag" {
    only       = ["docker.ubuntu"]
    repository = "quic-perf-runner"
    tags       = ["local"]
  }
}
