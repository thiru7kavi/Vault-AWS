
terraform {
  required_version = "0.12.0"
}

resource "aws_autoscaling_group" "autoscaling_group" {
  name_prefix = "${var.cluster_name}"

  launch_configuration = "${aws_launch_configuration.launch_configuration.name}"

  availability_zones  = ["${var.availability_zones}"]
  vpc_zone_identifier = ["${var.subnet_ids}"]

  # Use a fixed-size cluster
  min_size             = "${var.cluster_size}"
  max_size             = "${var.cluster_size}"
  desired_capacity     = "${var.cluster_size}"
  termination_policies = ["${var.termination_policies}"]

  health_check_type         = "${var.health_check_type}"
  health_check_grace_period = "${var.health_check_grace_period}"
  wait_for_capacity_timeout = "${var.wait_for_capacity_timeout}"

  enabled_metrics = ["${var.enabled_metrics}"]
  lifecycle {
    create_before_destroy = true
  }
}
resource "aws_launch_configuration" "launch_configuration" {
  name_prefix   = "${var.cluster_name}-"
  image_id      = "${var.ami_id}"
  instance_type = "${var.instance_type}"
  user_data     = "${var.user_data}"

  iam_instance_profile        = "${aws_iam_instance_profile.instance_profile.name}"
  key_name                    = "${var.ssh_key_name}"
  security_groups             = ["${concat(list(aws_security_group.lc_security_group.id), var.additional_security_group_ids)}"]
  placement_tenancy           = "${var.tenancy}"
  associate_public_ip_address = "${var.associate_public_ip_address}"

  ebs_optimized = "${var.root_volume_ebs_optimized}"

  root_block_device {
    volume_type           = "${var.root_volume_type}"
    volume_size           = "${var.root_volume_size}"
    delete_on_termination = "${var.root_volume_delete_on_termination}"
  }


  lifecycle {
    create_before_destroy = true
  }
}
resource "aws_security_group" "lc_security_group" {
  name_prefix = "${var.cluster_name}"
  description = "Security group for the ${var.cluster_name} configuration"
  vpc_id      = "${var.vpc_id}"
  lifecycle {
    create_before_destroy = true
  }

  tags = "${merge(map("Name", var.cluster_name), var.security_group_tags)}"
}

resource "aws_security_group_rule" "allow_ssh_inbound_from_cidr_blocks" {
  count       = "${length(var.allowed_ssh_cidr_blocks) >= 1 ? 1 : 0}"
  type        = "ingress"
  from_port   = "${var.ssh_port}"
  to_port     = "${var.ssh_port}"
  protocol    = "tcp"
  cidr_blocks = ["${var.allowed_ssh_cidr_blocks}"]

  security_group_id = "${aws_security_group.lc_security_group.id}"
}

resource "aws_security_group_rule" "allow_ssh_inbound_from_security_group_ids" {
  count                    = "${length(var.allowed_ssh_security_group_ids)}"
  type                     = "ingress"
  from_port                = "${var.ssh_port}"
  to_port                  = "${var.ssh_port}"
  protocol                 = "tcp"
  source_security_group_id = "${element(var.allowed_ssh_security_group_ids, count.index)}"

  security_group_id = "${aws_security_group.lc_security_group.id}"
}

resource "aws_security_group_rule" "allow_all_outbound" {
  type        = "egress"
  from_port   = 0
  to_port     = 0
  protocol    = "-1"
  cidr_blocks = ["0.0.0.0/0"]

  security_group_id = "${aws_security_group.lc_security_group.id}"
}


module "security_groups" {
  source = "../security_groups"

  security_group_id                    = "${aws_security_group.lc_security_group.id}"
  allowed_inbound_cidr_blocks          = ["${var.allowed_inbound_cidr_blocks}"]
  allowed_inbound_security_group_ids   = ["${var.allowed_inbound_security_group_ids}"]
  allowed_inbound_security_group_count = "${var.allowed_inbound_security_group_count}"

  api_port     = "${var.api_port}"
  cluster_port = "${var.cluster_port}"
}


resource "aws_iam_instance_profile" "instance_profile" {
  name_prefix = "${var.cluster_name}"
  path        = "${var.instance_profile_path}"
  role        = "${aws_iam_role.instance_role.name}"

  # aws_launch_configuration.launch_configuration in this module sets create_before_destroy to true, which means
  # everything it depends on, including this resource, must set it as well, or you'll get cyclic dependency errors
  # when you try to do a terraform destroy.
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_iam_role" "instance_role" {
  name_prefix        = "${var.cluster_name}"
  assume_role_policy = "${data.aws_iam_policy_document.instance_role.json}"

  # aws_iam_instance_profile.instance_profile in this module sets create_before_destroy to true, which means
  # everything it depends on, including this resource, must set it as well, or you'll get cyclic dependency errors
  # when you try to do a terraform destroy.
  lifecycle {
    create_before_destroy = true
  }
}

data "aws_iam_policy_document" "instance_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_dynamodb_table "dynamodb-table {
  name           = "${var.dynamoTable}"
  read_capacity  = 1
  write_capacity = 1
    hash_key       = "Path"
    range_key      = "Key"
    attribute      = [
        {
            name = "Path"
            type = "S"
        },
        {
            name = "Key"
            type = "S"
        }
  lifecycle {
    create_before_destroy = true
  }
}

data "aws_iam_policy_document" "vault_auto_unseal_kms" {
  count = "${var.enable_auto_unseal ? 1 : 0}"

  statement {
    effect = "Allow"

    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:DescribeKey",
    ]

    resources = ["${var.auto_unseal_kms_key_arn}"]
  }
}

resource "aws_iam_role_policy" "vault_auto_unseal_kms" {
  count  = "${var.enable_auto_unseal ? 1 : 0}"
  name   = "vault_auto_unseal_kms"
  role   = "${aws_iam_role.instance_role.id}"
  policy = "${element(concat(data.aws_iam_policy_document.vault_auto_unseal_kms.*.json, list("")), 0)}"
  lifecycle {
    create_before_destroy = true
  }
}