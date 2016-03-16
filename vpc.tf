resource "aws_security_group" "elb" {
  name = "${var.name}-lb"
  description = "Allows the load balancer to communicate with Elasticsearch nodes"

  vpc_id = "${var.vpc_id}"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group_rule" "elb_default" {
  type        = "ingress"
  from_port   = 9200
  to_port     = 9200
  protocol    = "tcp"
  cidr_blocks = ["0.0.0.0/0"]
  security_group_id = "${aws_security_group.elb.id}"
}

resource "aws_security_group_rule" "elb_http" {
  type        = "ingress"
  from_port   = 80
  to_port     = 80
  protocol    = "tcp"
  cidr_blocks = ["0.0.0.0/0"]
  security_group_id = "${aws_security_group.elb.id}"
}

resource "aws_security_group_rule" "elb_https" {
  type        = "ingress"
  from_port   = 443
  to_port     = 443
  protocol    = "tcp"
  cidr_blocks = ["0.0.0.0/0"]
  security_group_id = "${aws_security_group.elb.id}"
}

resource "aws_security_group_rule" "elb_es" {
  type        = "egress"
  from_port   = 9200
  to_port     = 9200
  protocol    = "tcp"
  source_security_group_id = "${aws_security_group.es.id}"
  security_group_id = "${aws_security_group.elb.id}"
}

resource "aws_security_group" "es" {
  name = "${var.name}-node"
  description = "Allows inter-node communication between Elasticsearch nodes"

  vpc_id = "${var.vpc_id}"

  ingress {
    from_port   = 9200
    to_port     = 9200
    protocol    = "tcp"
    self        = true
    security_groups = ["${aws_security_group.elb.id}"]
  }

  ingress {
    from_port   = 9300
    to_port     = 9300
    protocol    = "tcp"
    self        = true
  }

  egress {
    from_port   = 9200
    to_port     = 9200
    protocol    = "tcp"
    self        = true
  }

  egress {
    from_port   = 9300
    to_port     = 9300
    protocol    = "tcp"
    self        = true
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  lifecycle {
    create_before_destroy = true
  }
}
