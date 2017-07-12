variable "access_key" {}
variable "secret_key" {}
variable "region" {}
variable "vpc_id" {}
variable "ssh_key_name" {}
variable "count" {
  description = "Number of RabbitMQ nodes"
  default = 2
}
variable "subnet_ids" {
  description = "Subnets for RabbitMQ nodes"
  type = "list"
}
variable "security_group_ids" {
  description = "Security groups which should have access to ELB (amqp + http ports) and nodes (ssh port)"
  type = "list"
}
variable "admin_password" {
  description = "Password for 'admin' user"
  default = "password"
}
variable "rabbit_password" {
  description = "Password for 'rabbit' user"
  default = "password"
}
variable "rabbitmq_secret_cookie" {
  default = "supersecretcookie"
}
variable "instance_type" {
  default = "t2.small"
}
