data "azurerm_images" "runner" {
  resource_group_name = var.azure_resource_group

  tags_filter = {
    ManagedBy       = "packer"
    PackerLifecycle = "retained"
  }
}

data "azurerm_image" "runner" {
  name                = local.source_image_name
  resource_group_name = var.azure_resource_group
}

locals {
  image_names        = sort([for image in data.azurerm_images.runner.images : image.name if startswith(image.name, "quic-perf-runner-")])
  source_image_name  = local.image_names[length(local.image_names) - 1]
  source_location    = data.azurerm_image.runner.location
  source_image_id    = data.azurerm_image.runner.id
  needs_image_copy   = var.location != local.source_location
  gallery_name       = "quicperfrunner${substr(md5(var.name), 0, 12)}"
  vm_source_image_id = local.needs_image_copy ? azurerm_shared_image_version.runner[0].id : local.source_image_id
  benchmark_tags = {
    ManagedBy = "perf-dashboard"
    RunId     = var.name
  }
}

resource "azurerm_shared_image_gallery" "runner" {
  count               = local.needs_image_copy ? 1 : 0
  name                = local.gallery_name
  resource_group_name = var.azure_resource_group
  location            = local.source_location

  tags = local.benchmark_tags
}

resource "azurerm_shared_image" "runner" {
  count               = local.needs_image_copy ? 1 : 0
  name                = "quic-perf-runner"
  gallery_name        = azurerm_shared_image_gallery.runner[0].name
  resource_group_name = var.azure_resource_group
  location            = local.source_location
  os_type             = "Linux"
  hyper_v_generation  = "V2"

  identifier {
    publisher = "quic-go"
    offer     = "perf-dashboard"
    sku       = "runner"
  }

  tags = local.benchmark_tags
}

resource "azurerm_shared_image_version" "runner" {
  count               = local.needs_image_copy ? 1 : 0
  name                = "1.0.0"
  gallery_name        = azurerm_shared_image_gallery.runner[0].name
  image_name          = azurerm_shared_image.runner[0].name
  resource_group_name = var.azure_resource_group
  location            = local.source_location
  managed_image_id    = local.source_image_id

  deletion_of_replicated_locations_enabled = true

  target_region {
    name                   = local.source_location
    regional_replica_count = 1
    storage_account_type   = "Standard_LRS"
  }

  dynamic "target_region" {
    for_each = var.location == local.source_location ? [] : [var.location]

    content {
      name                   = target_region.value
      regional_replica_count = 1
      storage_account_type   = "Standard_LRS"
    }
  }

  tags = local.benchmark_tags

  timeouts {
    create = "2h"
    delete = "2h"
  }
}

resource "azurerm_virtual_network" "node" {
  name                = "${var.name}-vnet"
  address_space       = ["10.42.0.0/16"]
  location            = var.location
  resource_group_name = var.azure_resource_group

  tags = local.benchmark_tags
}

resource "azurerm_subnet" "node" {
  name                 = "default"
  resource_group_name  = var.azure_resource_group
  virtual_network_name = azurerm_virtual_network.node.name
  address_prefixes     = ["10.42.0.0/24"]
}

resource "azurerm_public_ip" "node" {
  name                = "${var.name}-ip"
  location            = var.location
  resource_group_name = var.azure_resource_group
  allocation_method   = "Static"
  sku                 = "Standard"

  tags = local.benchmark_tags
}

resource "azurerm_network_interface" "node" {
  name                = "${var.name}-nic"
  location            = var.location
  resource_group_name = var.azure_resource_group

  ip_configuration {
    name                          = "primary"
    subnet_id                     = azurerm_subnet.node.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.node.id
  }

  tags = local.benchmark_tags
}

resource "azurerm_network_security_group" "node" {
  name                = "${var.name}-nsg"
  location            = var.location
  resource_group_name = var.azure_resource_group

  security_rule {
    name                       = "allow-inbound"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  tags = local.benchmark_tags
}

resource "azurerm_network_interface_security_group_association" "node" {
  network_interface_id      = azurerm_network_interface.node.id
  network_security_group_id = azurerm_network_security_group.node.id
}

resource "azurerm_linux_virtual_machine" "node" {
  name                            = var.name
  resource_group_name             = var.azure_resource_group
  location                        = var.location
  size                            = "Standard_D2s_v5"
  admin_username                  = "perf"
  disable_password_authentication = true
  network_interface_ids           = [azurerm_network_interface.node.id]
  source_image_id                 = local.vm_source_image_id

  admin_ssh_key {
    username   = "perf"
    public_key = var.ssh_public_key
  }

  os_disk {
    name                 = "${var.name}-osdisk"
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  tags = local.benchmark_tags

  depends_on = [azurerm_network_interface_security_group_association.node]
}
