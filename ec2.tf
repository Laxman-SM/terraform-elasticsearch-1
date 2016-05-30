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

  desired_capacity = "${var.cluster_size}"
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
  alarm_description = "Increase the elasticsearch cluster when there is less than 10% free storage capacity"
  threshold = "${(var.volume_size * 1000000000) / 10}"
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
  threshold = "${(var.volume_size * 1.1) * 1000000000}"
  alarm_actions = ["${aws_autoscaling_policy.es_decrease.arn}"]
}

resource "template_file" "es" {
  template = <<TEMPLATE
#!/bin/bash -ei
NODE_NAME=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
if [ -z "$NODE_NAME" ]; then
  NODE_NAME=$(hostname)
fi

curl -s https://packages.elastic.co/GPG-KEY-elasticsearch | sudo apt-key add -
echo "deb http://packages.elastic.co/elasticsearch/${replace(elasticsearch_version, "/\.\d+$/", ".x")}/debian stable main" | sudo tee -a /etc/apt/sources.list.d/elasticsearch.list

sudo add-apt-repository ppa:webupd8team/java
echo "oracle-java8-installer shared/accepted-oracle-license-v1-1 select true" | sudo debconf-set-selections
sudo apt-get update
sudo apt-get install -y oracle-java8-installer oracle-java8-set-default elasticsearch

cat <<EOF | sudo tee /etc/elasticsearch/elasticsearch.yml
node.name: $NODE_NAME
cluster.name: ${cluster_name}
network.host: _site_
index.number_of_replicas: ${number_of_replicas}
discovery:
  type: ec2
  ec2:
    groups: "${security_groups}"
cloud.aws:
  region: "${region}"
EOF

/usr/share/elasticsearch/bin/plugin install cloud-aws

sudo service elasticsearch restart

cat <<EOF | sudo tee /etc/lifecycled
AWS_REGION=${region}
LIFECYCLED_DEBUG=true
LIFECYCLED_QUEUE=${lifecycle_queue}
LIFECYCLED_INSTANCEID=$NODE_NAME
LIFECYCLED_HANDLER=/usr/bin/elasticsearch-lifecycle-handler
EOF

sudo curl -Lf -o /usr/bin/lifecycled https://github.com/lox/lifecycled/releases/download/${lifecycled_version}/lifecycled-linux-x86_64
sudo chmod +x /usr/bin/lifecycled

sudo curl -Lf -o /etc/systemd/system/lifecycled.unit https://raw.githubusercontent.com/lox/lifecycled/${lifecycled_version}/init/systemd/lifecycled.conf

cat <<EOF | sudo tee /usr/bin/elasticsearch-lifecycle-handler
#!/bin/sh -eu
echo "stopping elasticsearch gracefully"
service elasticsearch stop
while pgrep -U $(id -u elasticsearch) > /dev/null; do
  sleep 0.5
done
echo "elasticsearch stopped!"
EOF

sudo chmod +x /usr/bin/elasticsearch-lifecycle-handler

sudo systemctl daemon-reload
sudo systemctl enable lifecycled
sudo systemctl start lifecycled
TEMPLATE

  vars {
    elasticsearch_version = "${var.elasticsearch_version}"
    lifecycled_version = "${var.lifecycled_version}"
    region = "${var.region}"
    security_groups = "${aws_security_group.es.id}"
    cluster_name = "${var.name}"
    number_of_replicas = "${var.cluster_size - 1}"
    lifecycle_queue = "${aws_sqs_queue.lifecycle.id}"
  }

  lifecycle {
    create_before_destroy = true
  }
}
