variable "access_key" {}
variable "secret_key" {}
variable "region" {}

variable "vpc_id" {}
variable "ssh_key_name" {}
variable "instance_type" {}
variable "subnet_ids" {
  type = "list"
}
variable "ssh_security_group_ids" {
  type = "list"
}
variable "elb_security_group_ids" {
  type = "list"
}

variable "rabbitmq_admin_password" {}
variable "rabbitmq_rabbit_password" {}
variable "rabbitmq_secret_cookie" {}
variable "rabbitmq_node_count" {}

provider "aws" {
  region     = "${var.region}"
  access_key = "${var.access_key}"
  secret_key = "${var.secret_key}"
}

module "rabbitmq" {
  source = "github.com/ulamlabs/rabbitmq-cluster"
  region = "${var.region}"
  vpc_id = "${var.vpc_id}"
  ssh_key_name = "${var.ssh_key_name}"
  instance_type = "${var.instance_type}"
  subnet_ids = "${var.subnet_ids}"
  ssh_security_group_ids = "${var.ssh_security_group_ids}"
  elb_security_group_ids = "${var.elb_security_group_ids}"
  admin_password = "${var.rabbitmq_admin_password}"
  rabbit_password = "${var.rabbitmq_rabbit_password}"
  rabbitmq_secret_cookie = "${var.rabbitmq_secret_cookie}"
  count = "${var.rabbitmq_node_count}"
}
