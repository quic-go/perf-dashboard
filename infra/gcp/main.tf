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
      image = "projects/${var.gcp_project_id}/global/images/family/quic-perf-runner"
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
