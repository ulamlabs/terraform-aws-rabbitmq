output "rabbitmq_elb_dns" {
  value = "${aws_elb.elb.dns_name}"
}
