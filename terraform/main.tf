terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# --------------------------------------------------------------------------
# Data Sources
# --------------------------------------------------------------------------

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# --------------------------------------------------------------------------
# VPC & Networking
# --------------------------------------------------------------------------

resource "aws_vpc" "lab" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name        = "ai-csl-wazuh-lab"
    Project     = "ai-csl-wazuh-lab"
    Environment = var.environment
  }
}

resource "aws_internet_gateway" "lab" {
  vpc_id = aws_vpc.lab.id

  tags = {
    Name    = "ai-csl-wazuh-lab-igw"
    Project = "ai-csl-wazuh-lab"
  }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.lab.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = true

  tags = {
    Name    = "ai-csl-wazuh-lab-public"
    Project = "ai-csl-wazuh-lab"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.lab.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.lab.id
  }

  tags = {
    Name    = "ai-csl-wazuh-lab-public-rt"
    Project = "ai-csl-wazuh-lab"
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# --------------------------------------------------------------------------
# Security Groups
# --------------------------------------------------------------------------

resource "aws_security_group" "wazuh_manager" {
  name        = "wazuh-manager-sg"
  description = "Security group for Wazuh manager"
  vpc_id      = aws_vpc.lab.id

  # SSH from your IP
  ingress {
    description = "SSH access"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.your_ip_cidr]
  }

  # Wazuh Dashboard (HTTPS)
  ingress {
    description = "Wazuh Dashboard"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.your_ip_cidr]
  }

  # Wazuh agent communication
  ingress {
    description = "Wazuh agent communication"
    from_port   = 1514
    to_port     = 1514
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  # Wazuh agent enrollment
  ingress {
    description = "Wazuh agent enrollment"
    from_port   = 1515
    to_port     = 1515
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  # Wazuh API
  ingress {
    description = "Wazuh API"
    from_port   = 55000
    to_port     = 55000
    protocol    = "tcp"
    cidr_blocks = [var.your_ip_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "wazuh-manager-sg"
    Project = "ai-csl-wazuh-lab"
  }
}

resource "aws_security_group" "wazuh_agent" {
  name        = "wazuh-agent-sg"
  description = "Security group for Wazuh agent"
  vpc_id      = aws_vpc.lab.id

  # SSH from your IP
  ingress {
    description = "SSH access"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.your_ip_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "wazuh-agent-sg"
    Project = "ai-csl-wazuh-lab"
  }
}

# --------------------------------------------------------------------------
# Elastic IP for Wazuh Manager
# --------------------------------------------------------------------------

resource "aws_eip" "wazuh_manager" {
  domain = "vpc"

  tags = {
    Name    = "wazuh-manager-eip"
    Project = "ai-csl-wazuh-lab"
  }
}

resource "aws_eip_association" "wazuh_manager" {
  instance_id   = aws_instance.wazuh_manager.id
  allocation_id = aws_eip.wazuh_manager.id
}

# --------------------------------------------------------------------------
# EC2 Instances
# --------------------------------------------------------------------------

resource "aws_instance" "wazuh_manager" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.manager_instance_type
  key_name               = var.key_name
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.wazuh_manager.id]

  root_block_device {
    volume_size = 30
    volume_type = "gp3"
    encrypted   = true
  }

  user_data = file("${path.module}/user_data/wazuh_manager.sh")

  tags = {
    Name        = "wazuh-manager"
    Project     = "ai-csl-wazuh-lab"
    Role        = "manager"
    Environment = var.environment
  }
}

resource "aws_instance" "wazuh_agent" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.agent_instance_type
  key_name               = var.key_name
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.wazuh_agent.id]

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
    encrypted   = true
  }

  user_data = templatefile("${path.module}/user_data/wazuh_agent.sh", {
    manager_ip = aws_instance.wazuh_manager.private_ip
  })

  depends_on = [aws_instance.wazuh_manager]

  tags = {
    Name        = "wazuh-agent"
    Project     = "ai-csl-wazuh-lab"
    Role        = "agent"
    Environment = var.environment
  }
}
