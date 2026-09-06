data "google_compute_image" "runner" {
  family  = "quic-perf-runner"
  project = var.gcp_project_id
}

resource "google_compute_instance" "node" {
  name         = var.name
  machine_type = "e2-medium"
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
      type  = "pd-balanced"
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
