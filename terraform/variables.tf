variable "aws_region" {
  description = "AWS region to deploy the lab into"
  type        = string
  default     = "us-east-1"
}

variable "your_ip_cidr" {
  description = "Your public IP in CIDR notation (e.g., 203.0.113.50/32). Used to restrict SSH and dashboard access."
  type        = string

  validation {
    condition     = can(cidrhost(var.your_ip_cidr, 0))
    error_message = "Must be a valid CIDR block (e.g., 203.0.113.50/32)."
  }
}

variable "key_name" {
  description = "Name of an existing EC2 key pair for SSH access"
  type        = string
}

variable "manager_instance_type" {
  description = "EC2 instance type for the Wazuh manager. t3.large recommended (8GB RAM for manager + indexer + dashboard). t3.medium works but dashboard will be slow."
  type        = string
  default     = "t3.large"
}

variable "agent_instance_type" {
  description = "EC2 instance type for the Wazuh agent"
  type        = string
  default     = "t3.micro"
}

variable "environment" {
  description = "Environment tag for all resources"
  type        = string
  default     = "lab"
}
