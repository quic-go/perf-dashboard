output "node" {
  value = {
    provider  = "gcp"
    location  = var.location
    name      = var.name
    public_ip = google_compute_instance.node.network_interface[0].access_config[0].nat_ip
    user      = "perf"
  }
}
