data "google_compute_image" "runner" {
  family  = "quic-perf-runner-${var.architecture}"
  project = var.gcp_project_id
}

resource "google_compute_firewall" "node" {
  name    = var.name
  network = "default"

  target_tags = ["quic-perf-runner"]

  allow {
    protocol = "udp"
    ports    = ["4433"]
  }

  source_ranges = ["0.0.0.0/0"]
}

resource "google_compute_instance" "node" {
  name         = var.name
  machine_type = var.machine_type
  zone         = var.location
  tags         = ["quic-perf-runner"]

  labels = {
    managed_by = "perf-dashboard"
    run_id     = var.name
  }

  boot_disk {
    auto_delete = true

    initialize_params {
      image = data.google_compute_image.runner.self_link
      size  = 20
    }
  }

  metadata = {
    enable-oslogin = "FALSE"
  }

  network_interface {
    network = "default"

    access_config {}
  }
}
