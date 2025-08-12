output "public_ip" {
  value = aws_instance.server.public_ip
}

output "flask_url" {
  value = "http://${aws_instance.server.public_ip}:5000/"
}