output "wazuh_dashboard_url" {
  description = "URL to access the Wazuh dashboard"
  value       = "https://${aws_eip.wazuh_manager.public_ip}"
}

output "manager_public_ip" {
  description = "Public IP of the Wazuh manager"
  value       = aws_eip.wazuh_manager.public_ip
}

output "agent_private_ip" {
  description = "Private IP of the Wazuh agent"
  value       = aws_instance.wazuh_agent.private_ip
}

output "ssh_manager_command" {
  description = "SSH command to connect to the Wazuh manager"
  value       = "ssh -i ~/.ssh/${var.key_name}.pem ubuntu@${aws_eip.wazuh_manager.public_ip}"
}

output "ssh_agent_command" {
  description = "SSH command to connect to the Wazuh agent (via manager as jump host)"
  value       = "ssh -i ~/.ssh/${var.key_name}.pem -J ubuntu@${aws_eip.wazuh_manager.public_ip} ubuntu@${aws_instance.wazuh_agent.private_ip}"
}
