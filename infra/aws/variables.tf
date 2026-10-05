variable "name" {
  type = string
}

variable "location" {
  type = string
}

variable "machine_type" {
  type    = string
  default = "c6i.large"
}

variable "architecture" {
  type    = string
  default = "amd64"
}

variable "aws_source_region" {
  type    = string
  default = "us-west-2"
}
