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

  listener {
    instance_port = 9200
    instance_protocol = "http"
    lb_port = 9200
    lb_protocol = "http"
  }

  health_check {
    healthy_threshold = 10
    unhealthy_threshold = 10
    timeout = 60
    target = "HTTP:9200/_cluster/health"
    interval = 300
  }
}

resource "aws_instance" "es" {
  count           = "${var.cluster_size}"
  instance_type   = "${var.instance_type}"
  ami             = "${coalesce(var.image_id, module.ami.ami_id)}"
  key_name        = "${var.key_name}"
  subnet_id       = "${element(split(",", var.subnet_ids), count.index)}"

  iam_instance_profile = "${aws_iam_instance_profile.es.id}"
  vpc_security_group_ids = ["${aws_security_group.es.id}"]

  user_data = "${template_file.es.rendered}"

  root_block_device {
    volume_type           = "gp2"
    volume_size           = "${var.volume_size_root}"
    delete_on_termination = true
  }

  ebs_block_device {
    device_name           = "/dev/sdf"
    volume_type           = "gp2"
    volume_size           = "${var.volume_size_data}"
    delete_on_termination = false
  }

  ephemeral_block_device {
    device_name  = "/dev/sdb"
    virtual_name = "ephemeral0"
  }

  tags {
    Role = "${var.name}"
  }

  lifecycle {
    create_before_destroy = true
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
    volume_size = "${var.volume_size_data}"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "es" {
  name = "${var.name}"
  health_check_grace_period = 300
  health_check_type = "EC2"

  min_size = "${var.cluster_size}"
  max_size = "${(var.cluster_size * 2) - 1}"
  vpc_zone_identifier = ["${split(",", var.subnet_ids)}"]

  launch_configuration = "${aws_launch_configuration.es.name}"
  load_balancers = ["${aws_elb.es.id}"]

  tag {
    key = "Name"
    value = "${var.name}"
    propagate_at_launch = true
  }

  tag {
    key = "Role"
    value = "elasticsearch-${var.name}"
    propagate_at_launch = true
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_lifecycle_hook" "lifecycle" {
  name = "${var.name}Lifecycle"
  autoscaling_group_name = "${aws_autoscaling_group.es.name}"
  lifecycle_transition = "autoscaling:EC2_INSTANCE_TERMINATING"
  notification_target_arn = "${aws_sqs_queue.lifecycle.arn}"
  role_arn = "${aws_iam_role.lifecycle.arn}"
}

resource "aws_autoscaling_policy" "es_increase" {
  name = "${var.name}CapacityIncrease"
  autoscaling_group_name = "${aws_autoscaling_group.es.name}"
  adjustment_type = "ChangeInCapacity"
  scaling_adjustment = 1
  cooldown = 300
}

resource "aws_autoscaling_policy" "es_decrease" {
  name = "${var.name}CapacityDecrease"
  autoscaling_group_name = "${aws_autoscaling_group.es.name}"
  adjustment_type = "ChangeInCapacity"
  scaling_adjustment = -1
  cooldown = 300
}

resource "aws_cloudwatch_metric_alarm" "es_low_storage" {
  alarm_name = "${var.name}LowStorage"
  comparison_operator = "LessThanThreshold"
  evaluation_periods = 2
  metric_name = "FreeStorage"
  namespace = "${var.name}"
  period = 900
  statistic = "Average"
  alarm_description = "Increase the elasticsearch cluster when there is less than ${var.scaling_free_storage_threshold}% free storage capacity"
  threshold = "${(var.volume_size_data * 1000000000.0) * (var.scaling_free_storage_threshold / 100.0)}"
  alarm_actions = ["${aws_autoscaling_policy.es_increase.arn}"]
}

resource "aws_cloudwatch_metric_alarm" "es_storage_surplus" {
  alarm_name = "${var.name}SurplusStorage"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods = 2
  metric_name = "FreeStorage"
  namespace = "${var.name}"
  period = 900
  statistic = "Average"
  alarm_description = "Decrease the elasticsearch cluster when there is more than a node's worth of storage capacity available"
  threshold = "${(var.volume_size_data * 1000000000.0) * (1.0 + (var.scaling_free_storage_threshold / 100.0))}"
  alarm_actions = ["${aws_autoscaling_policy.es_decrease.arn}"]
}

resource "template_file" "es" {
  template = "${file("${path.module}/user-data.txt")}"

  vars {
    elasticsearch_version = "${var.elasticsearch_version}"
    lifecycled_version = "${var.lifecycled_version}"
    region = "${var.region}"
    security_groups = "${aws_security_group.es.id}"
    cluster_name = "${var.name}"
    minimum_master_nodes = "${format("%d", (var.cluster_size / 2) + 1)}"
    number_of_replicas = "${var.cluster_size - 1}"
    ssh_keys = "${var.ssh_keys}"
    lifecycle_queue = "${aws_sqs_queue.lifecycle.id}"
  }

  lifecycle {
    create_before_destroy = true
  }
}
