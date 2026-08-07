variable "project_name" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "database_subnet_ids" {
  description = "DB 전용 서브넷. EKS 워커 서브넷과 분리된 대역이어야 함"
  type        = list(string)
}

variable "eks_node_security_group_id" {
  type = string
}

variable "engine" {
  type    = string
  default = "mysql"
}

variable "engine_version" {
  type    = string
  default = "8.0"
}

variable "db_port" {
  type    = number
  default = 3306
}

variable "instance_class" {
  type    = string
  default = "db.t3.micro"
}

variable "allocated_storage" {
  type    = number
  default = 20
}

variable "db_name" {
  type    = string
  default = "commondb"
}

variable "db_username" {
  type    = string
  default = "admin"
}

variable "common_tags" {
  type    = map(string)
  default = {}
}
