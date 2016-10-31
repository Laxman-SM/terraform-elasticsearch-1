provider "aws" {
  access_key = "${var.access_key}"
  secret_key = "${var.secret_key}"
  region     = "${var.region}"
}

data "aws_ami" "es" {
  most_recent = true
  executable_users = ["all", "self"]

  filter {
    name = "name"
    values = "*/hvm-ssd/ubuntu-xenial-16.04-amd64-server*"
  }

  filter {
    name = "architecture"
    values = "x86_64"
  }

  filter {
    name = "virtualization-type"
    values = "hvm"
  }

  filter {
    name = "hypervisor"
    values = "xen"
  }

  filter {
    name = "state"
    values = "available"
  }

  filter {
    name = "root-device-type"
    values = "ebs"
  }
}

output "dns_name" {
  value = "${aws_elb.es.dns_name}"
}

output "security_group_id" {
  value = "${aws_security_group.elb.id}"
}

output "ip" {
  value = "${join(",", aws_instance.es.*.private_ip)}"
}
