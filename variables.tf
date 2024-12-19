variable "aws_region" {
  description = "The AWS region to deploy resources"
  default     = "eu-west-1"
}

variable "db_username" {
  description = "The MySQL database username"
}

variable "db_password" {
  description = "The MySQL database password"
}

variable "key_name" {
  description = "The name of the EC2 key pair"
}

variable "instance_ami" {
  description = "The AMI ID for the EC2 instance"
}

variable "db_name" {
  description = "The MySQL database name"
}
