output "wazuh_dashboard_url" {
  description = "URL to access the Wazuh dashboard"
  value       = "https://${aws_eip.wazuh_manager.public_ip}"
}

output "manager_public_ip" {
  description = "Public IP of the Wazuh manager"
  value       = aws_eip.wazuh_manager.public_ip
}

output "manager_private_ip" {
  description = "Private IP of the Wazuh manager"
  value       = aws_instance.wazuh_manager.private_ip
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

output "get_passwords_command" {
  description = "Run this to retrieve all Wazuh passwords (admin, wazuh-wui, kibanaserver, etc.)"
  value       = "ssh -i ~/.ssh/${var.key_name}.pem ubuntu@${aws_eip.wazuh_manager.public_ip} 'sudo cat /root/wazuh-install-files/wazuh-passwords.txt'"
}

output "next_steps" {
  description = "What to do after terraform apply completes"
  value       = <<-EOT

    ========================================================
     CloudVault Wazuh Lab - Deployment Complete
    ========================================================

    Manager IP:     ${aws_eip.wazuh_manager.public_ip}
    Dashboard URL:  https://${aws_eip.wazuh_manager.public_ip}

    NEXT STEPS:

    1. Wait ~10-15 minutes for Wazuh to finish installing on the manager.
       Check progress:
         ssh -i ~/.ssh/${var.key_name}.pem ubuntu@${aws_eip.wazuh_manager.public_ip} 'sudo tail -f /var/log/wazuh-install.log'

    2. Get passwords once install finishes:
         ssh -i ~/.ssh/${var.key_name}.pem ubuntu@${aws_eip.wazuh_manager.public_ip} 'sudo cat /root/wazuh-install-files/wazuh-passwords.txt'

       Or run the full diagnostic:
         ./scripts/doctor.sh

    3. Open the dashboard: https://${aws_eip.wazuh_manager.public_ip}
       Username: admin
       Password: (from step 2 — look for the admin user)

    4. Agents auto-register. Verify at https://${aws_eip.wazuh_manager.public_ip}/app/endpoints-summary
       Expected: web-server-01, app-server-01, dev-server-01 all Active.

    COST: ~$0.11/hr running. Run 'terraform destroy' when done.

  EOT
}
