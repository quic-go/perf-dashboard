output "node" {
  value = {
    provider  = "aws"
    location  = var.location
    name      = var.name
    public_ip = aws_instance.node.public_ip
    user      = "perf"
  }
}
