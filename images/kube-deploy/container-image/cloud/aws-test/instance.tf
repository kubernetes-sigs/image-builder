provider "aws" {
  region = "us-east-2"
}

# Export the region, for scripts
output "test_instance_region" {
  value = "us-east-2"
}

variable "image_name" {
  type    = string
  default = "buster-aws"
}

# Use the default VPC
data "aws_vpc" "main" {
  default = true
}

data "aws_ami" "default" {
  most_recent = true

  filter {
    name   = "name"
    values = ["imagebuilder-${var.image_name}-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["self"]
}

# Allow inbound SSH
resource "aws_security_group" "allow_ssh" {
  description = "Allow SSH inbound traffic"
  vpc_id      = data.aws_vpc.main.id

  ingress {
    description = "Inbound SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Allow all outbound traffic
resource "aws_security_group" "allow_outbound" {
  description = "Allow all outbound traffic"
  vpc_id      = data.aws_vpc.main.id

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Upload our ssh key
resource "aws_key_pair" "default" {
  key_name   = "imagebuilder-aws-test"
  public_key = file("id_rsa.pub")
}

# Create a test instance
resource "aws_instance" "test" {
  vpc_security_group_ids = [aws_security_group.allow_ssh.id, aws_security_group.allow_outbound.id]
  key_name               = aws_key_pair.default.key_name

  associate_public_ip_address = true
  ami                         = data.aws_ami.default.id
  instance_type               = "t3.medium"

  root_block_device {
    volume_type = "gp2"
    volume_size = "40"
  }
}

# Output the instance information
output "test_instance_id" {
  value = aws_instance.test.id
}
output "test_instance_public_ip" {
  value = aws_instance.test.public_ip
}
