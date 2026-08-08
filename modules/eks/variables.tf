variable "cluster_name" {
  type = string
}

variable "kubernetes_version" {
  type    = string
  default = "1.35"
}

variable "vpc_id" {
  type = string
}

variable "private_subnet_ids" {
  type = list(string)
}

variable "node_instance_types" {
  type    = list(string)
  default = ["t3.medium"]
}

variable "node_min_size" {
  type    = number
  default = 1
}

variable "node_max_size" {
  type    = number
  default = 3
}

variable "node_desired_size" {
  type    = number
  default = 2
}

variable "common_tags" {
  type    = map(string)
  default = {}
}

variable "developer_iam_arns" {
  description = "클러스터 접근이 필요한 팀원 IAM ARN"
  type        = map(string)
  default     = {}
}