output "public_ip" {
  value = aws_eip.app.public_ip
}

output "check_before_cutover" {
  description = "Open this once first boot finishes (~10 min, the image builds on the instance)."
  value       = "http://${aws_eip.app.public_ip}/"
}

output "instance_id" {
  description = "For SSM: aws ssm start-session --target <id>"
  value       = aws_instance.app.id
}
