data "aws_ami" "runner" {
  provider    = aws.source
  most_recent = true
  owners      = ["self"]

  filter {
    name   = "tag:Name"
    values = ["quic-perf-runner"]
  }

  filter {
    name   = "tag:ManagedBy"
    values = ["packer"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}

resource "aws_ami_copy" "runner" {
  count             = var.location == var.aws_source_region ? 0 : 1
  name              = "${var.name}-${var.location}"
  source_ami_id     = data.aws_ami.runner.id
  source_ami_region = var.aws_source_region

  tags = {
    Name      = "quic-perf-runner"
    ManagedBy = "perf-dashboard"
    RunId     = var.name
  }
}

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }

  filter {
    name   = "default-for-az"
    values = ["true"]
  }
}

resource "aws_security_group" "node" {
  name        = var.name
  description = "Temporary QUIC perf node access"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "Allow inbound benchmark traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name      = var.name
    ManagedBy = "perf-dashboard"
    RunId     = var.name
  }
}

resource "aws_instance" "node" {
  ami                         = var.location == var.aws_source_region ? data.aws_ami.runner.id : aws_ami_copy.runner[0].id
  instance_type               = "c6i.large"
  subnet_id                   = sort(data.aws_subnets.default.ids)[0]
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.node.id]

  root_block_device {
    delete_on_termination = true
  }

  tags = {
    Name      = var.name
    ManagedBy = "perf-dashboard"
    RunId     = var.name
  }
}
