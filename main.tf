provider "aws" {
    region     = "${var.region}"
    access_key = "${var.access_key}"
    secret_key = "${var.secret_key}"
}

data "aws_vpc" "vpc" {
  id = "${var.vpc_id}"
}

data "aws_ami_ids" "ami" {
  owners = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn-ami-hvm-2017*-gp2"]
  }
}

data "aws_iam_policy_document" "policy_doc" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

data "template_file" "cloud-init" {
  template = "${file("${path.module}/cloud-init.yaml")}"

  vars {
    sync_node_count = 3
    region            = "${var.region}"
    secret_cookie     = "${var.rabbitmq_secret_cookie}"
    admin_password    = "${var.admin_password}"
    rabbit_password   = "${var.rabbit_password}"
    message_timeout   = "${3 * 24 * 60 * 60 * 1000}"  # 3 days
  }
}

resource "aws_iam_role" "role" {
  name               = "rabbitmq"
  assume_role_policy = "${data.aws_iam_policy_document.policy_doc.json}"
}

resource "aws_iam_role_policy" "policy" {
  name   = "rabbitmq"
  role   = "${aws_iam_role.role.id}"
  policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "autoscaling:DescribeAutoScalingInstances",
                "ec2:DescribeInstances"
            ],
            "Resource": [
                "*"
            ]
        }
    ]
}
EOF
}

resource "aws_iam_instance_profile" "profile" {
  name = "rabbitmq"
  role = "${aws_iam_role.role.name}"
}


resource "aws_security_group" "rabbitmq_elb" {
  name        = "rabbitmq_elb"
  vpc_id      = "${var.vpc_id}"
  description = "Security Group for the rabbitmq elb"

  ingress {
    protocol        = "tcp"
    from_port       = 5672
    to_port         = 5672
    security_groups = ["${var.security_group_ids}"]
  }

  ingress {
    protocol        = "tcp"
    from_port       = 80
    to_port         = 80
    security_groups = ["${var.security_group_ids}"]
  }

  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags {
    Name = "rabbitmq elb"
  }
}

resource "aws_security_group" "rabbitmq_nodes" {
  name        = "rabbitmq-nodes"
  vpc_id      = "${var.vpc_id}"
  description = "Security Group for the rabbitmq nodes"

  ingress {
    protocol  = -1
    from_port = 0
    to_port   = 0
    self      = true
  }

  ingress {
    protocol        = "tcp"
    from_port       = 5672
    to_port         = 5672
    security_groups = ["${aws_security_group.rabbitmq_elb.id}"]
  }

  ingress {
    protocol        = "tcp"
    from_port       = 15672
    to_port         = 15672
    security_groups = ["${aws_security_group.rabbitmq_elb.id}"]
  }

  ingress {
    protocol        = "tcp"
    from_port       = 22
    to_port         = 22
    security_groups = ["${var.security_group_ids}"]
  }

  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = [
      "0.0.0.0/0"
    ]
  }

  tags {
    Name = "rabbitmq nodes"
  }
}

resource "aws_launch_configuration" "rabbitmq" {
  name                 = "rabbitmq"
  image_id             = "${data.aws_ami_ids.ami.ids[0]}"
  instance_type        = "${var.instance_type}"
  key_name             = "${var.ssh_key_name}"
  security_groups      = ["${aws_security_group.rabbitmq_nodes.id}"]
  iam_instance_profile = "${aws_iam_instance_profile.profile.id}"
  user_data            = "${data.template_file.cloud-init.rendered}"
}

resource "aws_autoscaling_group" "rabbitmq" {
  name                      = "rabbitmq"
  max_size                  = "${var.count}"
  min_size                  = "${var.count}"
  desired_capacity          = "${var.count}"
  health_check_grace_period = 300
  health_check_type         = "ELB"
  force_delete              = true
  launch_configuration      = "${aws_launch_configuration.rabbitmq.name}"
  load_balancers            = ["${aws_elb.elb.name}"]
  vpc_zone_identifier       = "${var.subnet_ids}"
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
    interval            = 30
    unhealthy_threshold = 10
    healthy_threshold   = 2
    timeout             = 3
    target              = "TCP:5672"
  }

  subnets               = ["${var.subnet_ids}"]
  idle_timeout          = 3600
  internal              = true
  security_groups       = ["${aws_security_group.rabbitmq_elb.id}"]

  tags {
    Name = "rabbitmq"
  }
}
