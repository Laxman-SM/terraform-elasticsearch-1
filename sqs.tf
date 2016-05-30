resource "aws_sqs_queue" "lifecycle" {
  name = "${var.name}Lifecycle"
}
