output "node" {
  value = {
    provider     = "aws"
    region       = var.location
    zone         = aws_instance.node.availability_zone
    machine_type = aws_instance.node.instance_type
    image_id     = aws_instance.node.ami
    public_ip    = aws_instance.node.public_ip
  }
}
