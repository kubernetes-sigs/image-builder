provider "aws" {
  region = "us-east-2"
}

# Use the default VPC
data "aws_vpc" "main" {
  default = true
}

# Use the latest amazonlinux2 AMI
data "aws_ami" "amazonlinux2" {
  most_recent = true

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-2.0.????????.?-x86_64-gp2"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["amazon"]
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

# Upload our ssh key
resource "aws_key_pair" "default" {
  key_name   = "imagebuilder-aws-upload"
  public_key = file("id_rsa.pub")
}

# Create a worker instance
resource "aws_instance" "worker" {
  vpc_security_group_ids = ["${aws_security_group.allow_ssh.id}"]
  key_name               = aws_key_pair.default.key_name

  associate_public_ip_address = true
  ami                         = data.aws_ami.amazonlinux2.id
  instance_type               = "m5a.large"

  ebs_block_device {
    delete_on_termination = true
    volume_size           = 8
    volume_type           = "gp2"
    device_name           = "/dev/xvdj"
  }
}

# Output the instance id
output "worker_instance_id" {
  value = aws_instance.worker.id
}
