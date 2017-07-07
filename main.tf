provider "aws" {
    region = "${var.region}"
    access_key = "${var.access_key}"
    secret_key = "${var.secret_key}"
}

data "aws_vpc" "vpc" {
  id = "${var.vpc_id}"
}

data "aws_route53_zone" "selected" {
  zone_id = "${var.route53_zone_id}"
}

data "aws_ami_ids" "ami" {
  owners = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn-ami-hvm-2017*-gp2"]
  }
}

data "null_data_source" "nodes" {
  count = "${var.count}"
  inputs = {
    name = "rabbit-${count.index}"
    domain = "rabbit-${count.index}.${substr(data.aws_route53_zone.selected.name, 0, length(data.aws_route53_zone.selected.name) - 1)}"
    node_name = "rabbit@rabbit-${count.index}.${substr(data.aws_route53_zone.selected.name, 0, length(data.aws_route53_zone.selected.name) - 1)}"
  }
}

resource "aws_security_group" "rabbitmq_elb" {
  name = "rabbitmq_elb"
  vpc_id = "${var.vpc_id}"
  description = "Security Group for the rabbitmq elb"

  ingress {
    protocol = "tcp"
    from_port = 5672
    to_port = 5672
    security_groups = ["${var.security_group_ids}"]
  }

  ingress {
    protocol = "tcp"
    from_port = 80
    to_port = 80
    security_groups = ["${var.security_group_ids}"]
  }

  egress {
    protocol = "-1"
    from_port = 0
    to_port = 0
    cidr_blocks = [
      "0.0.0.0/0"
    ]
  }

  tags {
    Name = "rabbitmq elb"
  }
}

resource "aws_security_group" "rabbitmq_nodes" {
  name = "rabbitmq-nodes"
  vpc_id = "${var.vpc_id}"
  description = "Security Group for the rabbitmq nodes"

  ingress {
    protocol = -1
    from_port = 0
    to_port = 0
    self = true
  }

  ingress {
    protocol = "tcp"
    from_port = 5672
    to_port = 5672
    security_groups = ["${aws_security_group.rabbitmq_elb.id}"]
  }

  ingress {
    protocol = "tcp"
    from_port = 15672
    to_port = 15672
    security_groups = ["${aws_security_group.rabbitmq_elb.id}"]
  }

  ingress {
    protocol = "tcp"
    from_port = 22
    to_port = 22
    security_groups = ["${var.security_group_ids}"]
  }

  egress {
    protocol = "-1"
    from_port = 0
    to_port = 0
    cidr_blocks = [
      "0.0.0.0/0"
    ]
  }

  tags {
    Name = "rabbitmq nodes"
  }
}

data "template_file" "cloud-init" {
  count = "${var.count}"
  template = "${file("${path.module}/cloud-init.yaml")}"

  vars {
    majority = "${floor(var.count / 2) + 1}"
    nodes = "${join(", ", formatlist("'%s'", data.null_data_source.nodes.*.inputs.node_name))}"
    hostname = "${element(data.null_data_source.nodes.*.inputs.domain, count.index)}"
    secret_cookie = "${var.rabbitmq_secret_cookie}"
    admin_password = "${var.admin_password}"
    rabbit_password = "${var.rabbit_password}"
    message_timeout = "${3 * 24 * 60 * 60 * 1000}"  # 3 days
  }
}

resource "aws_instance" "rabbitmq" {
    count = "${var.count}"
    subnet_id = "${element(var.subnet_ids, count.index)}"
    ami = "${data.aws_ami_ids.ami.ids[0]}"
    instance_type = "${var.instance_type}"
    key_name = "${var.ssh_key_name}"
    vpc_security_group_ids = ["${aws_security_group.rabbitmq_nodes.id}"]
    associate_public_ip_address = false
    user_data = "${element(data.template_file.cloud-init.*.rendered, count.index)}"
    tags {
        Name = "rabbitmq-${count.index}"
    }
}

resource "aws_route53_record" "rabbit" {
  count = "${var.count}"
  zone_id = "${var.route53_zone_id}"
  name    = "rabbit-${count.index}"
  type    = "A"
  ttl     = "300"
  records = ["${element(aws_instance.rabbitmq.*.private_ip, count.index)}"]
}

resource "aws_elb" "elb" {
  name                 = "rabbit-elb"

  listener {
    instance_port      = 5672
    instance_protocol  = "tcp"
    lb_port            = 5672
    lb_protocol        = "tcp"
  }

  listener {
    instance_port      = 15672
    instance_protocol  = "http"
    lb_port            = 80
    lb_protocol        = "http"
  }

  health_check {
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 3
    target              = "TCP:5672"
    interval            = 30
  }

  instances             = ["${aws_instance.rabbitmq.*.id}"]
  subnets               = ["${var.subnet_ids}"]
  idle_timeout          = 3600
  internal              = true
  security_groups       = ["${aws_security_group.rabbitmq_elb.id}"]

  tags {
    Name = "rabbitmq"
  }
}

resource "aws_route53_record" "elb" {
  zone_id = "${var.route53_zone_id}"
  name    = "rabbit"
  type    = "CNAME"
  ttl     = "300"
  records = ["${aws_elb.elb.dns_name}"]
}
