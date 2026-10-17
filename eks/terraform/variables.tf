variable "aws_region" {
  type    = string
  default = "ap-southeast-2"
}

variable "project_name" {
  type    = string
  default = "demo-app"
}

variable "cluster_name" {
  description = "EKS cluster name. The workflows use the same default, so change both together."
  type        = string
  default     = "demo-app-eks"
}

variable "kubernetes_version" {
  description = "Leave null to let AWS use its current default version (avoids paid extended support on old versions)."
  type        = string
  default     = null
}

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

# EKS needs subnets in at least 2 Availability Zones
variable "public_subnet_cidrs" {
  type    = list(string)
  default = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "node_instance_type" {
  description = "t3.micro is too small for EKS (max 4 pods per node). t3.small is the cheapest sensible choice."
  type        = string
  default     = "t3.small"
}

variable "node_min_size" {
  type    = number
  default = 2
}

variable "node_desired_size" {
  type    = number
  default = 2
}

variable "node_max_size" {
  type    = number
  default = 3
}
