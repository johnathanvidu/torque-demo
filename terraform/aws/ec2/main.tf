data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-*-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_security_group" "allow_ssh" {
  name        = "allow_ssh"
  description = "Allow SSH inbound traffic"
  vpc_id      = var.vpc_id

  ingress {
    description = "SSH from allowed CIDRs"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.ssh_ingress_cidrs
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
}

# Random suffix so the key pair name is unique and avoids collisions on re-create.
resource "random_string" "key_suffix" {
  length  = 6
  special = false
  upper   = false
}

# Generate an SSH key pair. The private key is exposed via a (sensitive) output.
resource "tls_private_key" "this" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "this" {
  key_name   = "${var.instance_name}-${random_string.key_suffix.result}"
  public_key = tls_private_key.this.public_key_openssh
}

module "ec2_instance" {
  source  = "terraform-aws-modules/ec2-instance/aws"
  version = "5.8.0"

  name          = var.instance_name
  instance_type = var.instance_type
  ami           = data.aws_ami.ubuntu.id

  subnet_id                   = var.subnet_id
  vpc_security_group_ids      = concat([aws_security_group.allow_ssh.id], var.security_group_ids)
  associate_public_ip_address = true
  key_name                    = aws_key_pair.this.key_name
}
