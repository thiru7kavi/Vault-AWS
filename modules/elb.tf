

terraform {
  required_version = "0.12.0"
}

resource "aws_elb" "vault" {
  name = "${var.name}"

  internal                    = "${var.internal}"
  cross_zone_load_balancing   = "${var.cross_zone_load_balancing}"
  idle_timeout                = "${var.idle_timeout}"
  connection_draining         = "${var.connection_draining}"
  connection_draining_timeout = "${var.connection_draining_timeout}"

  security_groups = ["${aws_security_group.vault.id}"]
  subnets         = ["${var.subnet_ids}"]

  listener {
    lb_port           = "${var.lb_port}"
    lb_protocol       = "TCP"
    instance_port     = "${var.vault_api_port}"
    instance_protocol = "TCP"
  }

  health_check {
    target              = "${var.health_check_protocol}:${var.health_check_port == 0 ? var.vault_api_port : var.health_check_port}${var.health_check_path}"
    interval            = "${var.health_check_interval}"
    healthy_threshold   = "${var.health_check_healthy_threshold}"
    unhealthy_threshold = "${var.health_check_unhealthy_threshold}"
    timeout             = "${var.health_check_timeout}"
  }

  tags = "${merge(var.load_balancer_tags, map("Name", var.name))}"
}

resource "aws_autoscaling_attachment" "vault" {
  autoscaling_group_name = "${var.vault_asg_name}"
  elb                    = "${aws_elb.vault.id}"
}

resource "aws_security_group" "vault" {
  name        = "${var.name}-elb"
  description = "Security group for the ${var.name} ELB"
  vpc_id      = "${var.vpc_id}"

  tags = "${var.security_group_tags}"
}

resource "aws_security_group_rule" "allow_inbound_api" {
  type        = "ingress"
  from_port   = "${var.lb_port}"
  to_port     = "${var.lb_port}"
  protocol    = "tcp"
  cidr_blocks = ["${var.allowed_inbound_cidr_blocks}"]

  security_group_id = "${aws_security_group.vault.id}"
}

resource "aws_security_group_rule" "allow_all_outbound" {
  type        = "egress"
  from_port   = 0
  to_port     = 0
  protocol    = "-1"
  cidr_blocks = ["0.0.0.0/0"]

  security_group_id = "${aws_security_group.vault.id}"
}

