data "azurerm_shared_image_version" "runner" {
  name                    = "latest"
  gallery_name            = "quicperfrunner"
  image_name              = "quic-perf-runner"
  resource_group_name     = var.azure_resource_group
  sort_versions_by_semver = true
}

locals {
  source_location    = data.azurerm_shared_image_version.runner.location
  source_image_id    = data.azurerm_shared_image_version.runner.id
  needs_image_copy   = var.location != local.source_location
  gallery_name       = "quicperfrunner${substr(md5(var.name), 0, 12)}"
  vm_source_image_id = local.needs_image_copy ? "${azurerm_shared_image.runner[0].id}/versions/1.0.0" : local.source_image_id
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

# AzureRM's shared_image_version only accepts managed images or VMs as sources.
# A template lets us copy a gallery version without adding another provider.
resource "azurerm_resource_group_template_deployment" "runner" {
  count               = local.needs_image_copy ? 1 : 0
  name                = "${var.name}-image"
  resource_group_name = var.azure_resource_group
  deployment_mode     = "Incremental"

  template_content = jsonencode({
    "$schema"      = "https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#"
    contentVersion = "1.0.0.0"
    resources = [{
      type       = "Microsoft.Compute/galleries/images/versions"
      apiVersion = "2023-07-03"
      name       = "${azurerm_shared_image_gallery.runner[0].name}/${azurerm_shared_image.runner[0].name}/1.0.0"
      location   = local.source_location
      tags       = local.benchmark_tags
      properties = {
        storageProfile = { source = { id = local.source_image_id } }
        publishingProfile = {
          replicaCount       = 1
          storageAccountType = "Standard_LRS"
          targetRegions      = [for region in [local.source_location, var.location] : { name = region }]
        }
        safetyProfile = { allowDeletionOfReplicatedLocations = true }
      }
    }]
  })

  tags = local.benchmark_tags

  timeouts {
    # leave time for VM creation and state upload before the GitHub Actions job's limit
    create = "20m"
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
  name                           = "${var.name}-nic"
  location                       = var.location
  resource_group_name            = var.azure_resource_group
  accelerated_networking_enabled = true

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
  size                            = var.machine_type
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

  timeouts {
    create = "10m"
  }

  depends_on = [
    azurerm_network_interface_security_group_association.node,
    azurerm_resource_group_template_deployment.runner,
  ]
}
