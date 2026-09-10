variable "name" {
  type = string
}

variable "location" {
  type = string
}

variable "machine_type" {
  type    = string
  default = "Standard_D2s_v5"
}

variable "azure_subscription_id" {
  type = string
}

variable "azure_resource_group" {
  type = string
}

variable "ssh_public_key" {
  type = string
}
