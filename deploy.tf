
terraform {
  required_version = "0.12.0"
}




module "deploy_vault_cluster" {

  source = "./modules/deploy_vault_cluster"
  cluster_name  = "${var.vault_cluster_name}"
  cluster_size  = "${var.vault_cluster_size}"
  instance_type = "${var.vault_instance_type}"

  ami_id    = "${var.ami_id}"

  vpc_id     = "${data.aws_vpc.default.id}"
  subnet_ids = "${data.aws_subnet_ids.default.ids}"
  vault_asg_name = "${module.vault_cluster.asg_name}"
  allowed_ssh_cidr_blocks              = ["10.0.0.0/16"]
  allowed_inbound_cidr_blocks          = ["10.0.0.0/16"]
  allowed_inbound_security_group_ids   = []
  allowed_inbound_security_group_count = 0
  ssh_key_name                         = "${var.ssh_key_name}"
}


module "security_groups" {
  source = "./modules/security_groups"
  security_group_id = "${module.vault_cluster.security_group_id}"
  allowed_inbound_cidr_blocks = ["10.0.0.0/16"]
}

module "elb" {
  source = "./modules/elb"
  name = "${var.vault_cluster_name}"
  vpc_id     = "${data.aws_vpc.default.id}"
  subnet_ids = "${data.aws_subnet_ids.default.ids}"
  allowed_inbound_cidr_blocks = ["10.0.0.0/16"]
}

data "aws_vpc" "default" {
  default = "${var.use_default_vpc}"
  tags    = "${var.vpc_tags}"
}

data "aws_subnet_ids" "default" {
  vpc_id = "${data.aws_vpc.default.id}"
  tags   = "${var.subnet_tags}"
}

data "aws_region" "current" {}