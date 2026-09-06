output "node" {
  value = {
    provider     = "gcp"
    region       = regex("^(.+)-[a-z]$", google_compute_instance.node.zone)[0]
    zone         = google_compute_instance.node.zone
    machine_type = google_compute_instance.node.machine_type
    image_id     = data.google_compute_image.runner.self_link
    public_ip    = google_compute_instance.node.network_interface[0].access_config[0].nat_ip
  }
}
