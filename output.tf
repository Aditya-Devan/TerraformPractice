output "ec2_public_ip" {
  description = "Public IPv4 address of EC2"
  value       = aws_instance.web.public_ip
}

output "ec2_public_dns" {
  description = "Public DNS name of EC2"
  value       = aws_instance.web.public_dns
}