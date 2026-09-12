variable "name" {
  type = string
}

variable "location" {
  type = string
}

variable "machine_type" {
  type    = string
  default = "e2-medium"
}

variable "gcp_project_id" {
  type = string
}
