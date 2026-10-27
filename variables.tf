variable "ami_id" {
  description = "Ubuntu AMI ID for the selected AWS region"
  type        = string
  default     = "ami-0c7632fb77f35db43"
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.micro"
}

variable "allowed_ssh_cidr" {
  description = "Public IPv4 CIDR allowed to SSH into EC2"
  type        = string
  default     = "223.233.80.33/32"
}