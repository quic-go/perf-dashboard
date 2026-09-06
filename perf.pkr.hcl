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
  image_name = "quic-perf-runner-${formatdate("YYYYMMDDhhmmss", timestamp())}"
}

# The Docker image is only used for local development.
source "docker" "ubuntu" {
  image    = "ubuntu:24.04"
  platform = "linux/amd64"
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
      name                = "ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"
      root-device-type    = "ebs"
      virtualization-type = "hvm"
    }
    most_recent = true
    owners      = ["099720109477"]
  }

  ami_name        = local.image_name
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
  project_id = var.gcp_project_id
  zone       = "us-west1-b"

  source_image_family = "ubuntu-2404-lts-amd64"
  image_name          = local.image_name
  image_family        = "quic-perf-runner"

  machine_type = "e2-medium"
  disk_size    = 20 # GB

  ssh_username = "packer"
  communicator = "ssh"

  disable_default_service_account = true

  tags = ["packer"]
}

source "azure-arm" "ubuntu" {
  use_azure_cli_auth = true

  build_resource_group_name         = var.azure_resource_group
  managed_image_resource_group_name = var.azure_resource_group
  managed_image_name                = local.image_name

  os_type         = "Linux"
  image_publisher = "Canonical"
  image_offer     = "ubuntu-24_04-lts"
  image_sku       = "server"
  image_version   = "latest"

  vm_size         = "Standard_D2s_v5"
  os_disk_size_gb = 30

  # This lifecycle tag is Azure-only on purpose. AWS and GCP use Packer's normal
  # temporary resource cleanup, and our cleanup workflow only prunes their final
  # images. Azure builds run in our existing resource group because the service
  # principal is scoped there; if Packer or CI dies before Packer can clean up,
  # resources can be left behind. The workflow retags the final managed image as
  # retained after a successful build and deletes temporary leftovers later.
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
      "sudo apt-get update && sudo apt-get install -y ca-certificates curl git jq",
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
      "curl -fsSL 'https://go.dev/dl/go${var.go_version}.linux-amd64.tar.gz' -o /tmp/go.tar.gz",
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
    execute_command  = "sudo {{ .Vars }} {{ .Path }}"
    environment_vars = ["BUILD_COMMIT=${var.build_commit}"]
    inline = [<<-EOF
      mkdir -p /opt/quic-perf
      jq -n \
        --arg built_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        --arg build_commit "$BUILD_COMMIT" \
        --arg perf_commit "$(git -C /opt/quic-go/perf rev-parse HEAD)" \
        --arg quic_go_commit "$(git -C /opt/quic-go/quic-go rev-parse HEAD)" \
        --arg msquic_commit "$(git -C /opt/msquic rev-parse HEAD)" \
        --arg go_version "$(go version /opt/quic-go/perf/quic-go-perf | awk '{print $NF}')" \
        --arg cxx_version "$(c++ -dumpfullversion -dumpversion)" \
        '{
          schema_version: 1,
          built_at: $built_at,
          perf_dashboard_commit: $build_commit,
          implementations: {
            "quic-go": {commit: $quic_go_commit, perf_commit: $perf_commit, go_version: $go_version},
            "msquic": {commit: $msquic_commit, cxx_version: $cxx_version}
          }
        }' > /opt/quic-perf/build-info.json
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
    custom_data = {
      image_name = local.image_name
    }
  }

  post-processor "docker-tag" {
    only       = ["docker.ubuntu"]
    repository = "quic-perf-runner"
    tags       = ["local"]
  }
}
