output "node" {
  value = {
    provider     = "azure"
    region       = azurerm_linux_virtual_machine.node.location
    zone         = azurerm_linux_virtual_machine.node.zone
    machine_type = azurerm_linux_virtual_machine.node.size
    image_id     = azurerm_linux_virtual_machine.node.source_image_id
    public_ip    = azurerm_public_ip.node.ip_address
  }
}
