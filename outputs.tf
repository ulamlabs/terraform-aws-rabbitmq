output "rabbitmq_elb_dns" {
  value = aws_elb.elb.dns_name
}

output "admin_password" {
  value     = random_password.admin_password.result
  sensitive = true
}

output "rabbit_password" {
  value     = random_password.rabbit_password.result
  sensitive = true
}

output "secret_cookie" {
  value     = random_password.secret_cookie.result
  sensitive = true
}

