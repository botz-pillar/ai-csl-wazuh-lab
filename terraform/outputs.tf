output "wazuh_dashboard_url" {
  description = "URL to access the Wazuh dashboard"
  value       = "https://${aws_eip.wazuh_manager.public_ip}"
}

output "manager_public_ip" {
  description = "Public IP of the Wazuh manager"
  value       = aws_eip.wazuh_manager.public_ip
}

output "wazuh_api_url" {
  description = "Wazuh API URL (for MCP server config)"
  value       = "https://${aws_eip.wazuh_manager.public_ip}:55000"
}

output "wazuh_indexer_url" {
  description = "Wazuh Indexer URL (for MCP server alert queries)"
  value       = "https://${aws_eip.wazuh_manager.public_ip}:9200"
}

output "cloudvault_agents" {
  description = "CloudVault Financial agent instances"
  value = {
    for name, instance in aws_instance.cloudvault_agent : name => {
      public_ip  = instance.public_ip
      private_ip = instance.private_ip
      ssh        = "ssh -i ~/.ssh/${var.key_name}.pem ubuntu@${instance.public_ip}"
    }
  }
}

output "ssh_manager_command" {
  description = "SSH command to connect to the Wazuh manager"
  value       = "ssh -i ~/.ssh/${var.key_name}.pem ubuntu@${aws_eip.wazuh_manager.public_ip}"
}

output "mcp_config" {
  description = "Values needed for MCP server configuration"
  sensitive   = true
  value       = <<-EOT
    WAZUH_API_URL=https://${aws_eip.wazuh_manager.public_ip}:55000
    WAZUH_API_USER=wazuh-wui
    WAZUH_API_PASSWORD=[get from: sudo cat /root/wazuh-install-files/wazuh-passwords.txt]
    WAZUH_INDEXER_HOST=${aws_eip.wazuh_manager.public_ip}
    WAZUH_INDEXER_PORT=9200
    WAZUH_INDEXER_USER=admin
    WAZUH_INDEXER_PASSWORD=[get from same file]
  EOT
}
