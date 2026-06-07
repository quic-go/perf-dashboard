output "node" {
  value = {
    provider  = "azure"
    location  = var.location
    name      = var.name
    public_ip = azurerm_public_ip.node.ip_address
    user      = "perf"
  }
}
