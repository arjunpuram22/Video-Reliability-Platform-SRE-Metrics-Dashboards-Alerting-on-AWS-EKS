variable "region" { type = string }
variable "project" { type = string }
variable "env" { type = string }

variable "vpc_cidr" { type = string }

variable "cluster_name" { type = string }
variable "k8s_version" { type = string }

variable "node_instance_types" { type = list(string) }
variable "node_desired_size" { type = number }
variable "node_min_size" { type = number }
variable "node_max_size" { type = number }

variable "db_name" { type = string }
variable "db_user" { type = string }
variable "db_password" {
  type      = string
  sensitive = true
}
variable "db_instance_class" { type = string }
variable "db_allocated_storage" { type = number }

# Restrict EKS public endpoint access to your IP (recommended)
variable "eks_public_access_cidrs" {
  type    = list(string)
  default = ["0.0.0.0/0"]
}
