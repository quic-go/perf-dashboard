provider "aws" {
  alias  = "source"
  region = var.aws_source_region
}

provider "aws" {
  region = var.location
}
