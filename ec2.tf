resource "aws_elb" "es" {
  connection_draining = true
  cross_zone_load_balancing = true

  name = "${replace(lower(var.name), "e[^a-z0-9]+/", "-")}"
  subnets = ["${split(",", var.subnet_ids)}"]
  internal = "${var.internal_elb}"

  security_groups = ["${aws_security_group.elb.id}"]

  listener {
    instance_port = 9200
    instance_protocol = "http"
    lb_port = 80
    lb_protocol = "http"
  }

  health_check {
    healthy_threshold = 2
    unhealthy_threshold = 2
    timeout = 3
    target = "HTTP:9200/_cluster/health"
    interval = 30
  }
}

resource "aws_launch_configuration" "es" {
  name_prefix = "${var.name}-"

  image_id = "${coalesce(var.image_id, module.ami.ami_id)}"
  instance_type = "${var.instance_type}"
  key_name = "${var.key_name}"

  security_groups = ["${aws_security_group.es.id}"]
  iam_instance_profile = "${aws_iam_instance_profile.es.arn}"
  user_data = "${template_file.es.rendered}"

  root_block_device {
    volume_type = "gp2"
    volume_size = "${var.volume_size}"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "es" {
  name = "${var.name}"
  health_check_grace_period = 300
  health_check_type = "ELB"

  min_size = "${var.cluster_size}"
  max_size = "${var.cluster_size}"
  vpc_zone_identifier = ["${split(",", var.subnet_ids)}"]

  launch_configuration = "${aws_launch_configuration.es.name}"
  load_balancers = ["${aws_elb.es.id}"]

  tag {
    key = "Name"
    value = "${var.name}"
    propagate_at_launch = true
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "template_file" "es" {
  template = "${file("user-data.txt")}"

  vars {
    elasticsearch_version = "${var.elasticsearch_version}"
    region = "${var.region}"
    security_groups = "${aws_security_group.es.id}"
    cluster_name = "${var.name}"
  }

  lifecycle {
    create_before_destroy = true
  }
}