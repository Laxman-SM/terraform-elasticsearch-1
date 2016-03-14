resource "aws_iam_policy" "es" {
  name = "${var.name}Access"
  description = "Allows listing EC2 instances. Used by elasticsearch for cluster discovery"
  policy = <<POLICY
{
  "Statement": [
    {
      "Action": [
        "ec2:DescribeInstances"
      ],
      "Effect": "Allow",
      "Resource": [
        "*"
      ]
    }
  ],
  "Version": "2012-10-17"
}
POLICY
}

resource "aws_iam_policy_attachment" "es" {
  name = "${var.name}Attachment"
  roles = ["${aws_iam_role.es.name}"]
  policy_arn = "${aws_iam_policy.es.arn}"
}

resource "aws_iam_role" "es" {
  name = "${var.name}Node"
  assume_role_policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
POLICY

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_iam_instance_profile" "es" {
  name = "${var.name}Node"
  roles = ["${aws_iam_role.es.name}"]

  lifecycle {
    create_before_destroy = true
  }
}
