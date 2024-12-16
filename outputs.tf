# Output the API Gateway endpoint URL
output "api_gateway_url" {
  description = "The URL of the API Gateway endpoint"
  value       = aws_apigatewayv2_stage.my_stage.invoke_url
}

# Output the EC2 instance's public IP
output "ec2_public_ip" {
  description = "The public IP of the EC2 instance"
  value       = aws_instance.my_ec2.public_ip
}
