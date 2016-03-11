resource "aws_iam_policy" "es" {
  name = "${var.name}Access"
  description = "Allows listing EC2 instances. Used by elasticsearch for cluster discovery"
  policy = "${file("policy.json")}"
}

resource "aws_iam_policy_attachment" "es" {
  name = "${var.name}Attachment"
  roles = ["${aws_iam_role.es.name}"]
  policy_arn = "${aws_iam_policy.es.arn}"
}

resource "aws_iam_role" "es" {
  name = "${var.name}Node"
  assume_role_policy = "${file("assume-role-policy.json")}"

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
