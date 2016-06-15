variable "access_key" {
  default = ""
  description = "The AWS access key"
}

variable "secret_key" {
  default = ""
  description = "The AWS secret key"
}

variable "region" {
  default = "us-east-1"
  description = "The AWS region"
}

variable "key_name" {
  description = "The key name for the instances"
}

variable "subnet_ids" {
  description = "The subnet ID to use for the instances"
}

variable "vpc_id" {
  description = "The VPC ID"
}

variable "image_id" {
  default = ""
  description = "The Debian-based AMI to use"
}

variable "instance_type" {
  default = "m3.medium"
  description = "The EC2 instance type to use"
}

variable "volume_size_root" {
  default = 50
  description = "Size of the cluster"
}

variable "volume_size_data" {
  default = 1000
  description = "Size of the cluster"
}

variable "cluster_size" {
  default = 3
  description = "Size of the cluster"
}

variable "scaling_free_storage_threshold" {
  default = 15
  description = "Scale when free storage is or below this threshold"
}

variable "name" {
  default = "elasticsearch"
  description = "The elasticsearch cluster name"
}

variable "ssh_keys" {
  description = "Add ssh keys to the cluster"
}

variable "internal_elb" {
  default = true
  description = "Make the elastic load balancer internally accessible"
}

variable "elasticsearch_version" {
  default = "2.3"
  description = "The version of elasticsearch to install"
}

variable "lifecycled_version" {
  default = "v1.1.2"
  description = "The version of lifecycled to install"
}
