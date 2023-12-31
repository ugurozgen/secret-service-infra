variable "project_name" {
  default = "project_name"
}

variable "project_env" {
  default = "project_env"
}

variable "region" {
  default = "eu-north-1"
}

variable "vpc_id" {
  default = "vpc_id"
}

variable "vpc_private_subnets" {
  default = []
}

variable "ebscsi_policy" {
  default = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}
