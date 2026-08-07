variable "project_name" {
  type = string
}

variable "cluster_name" {
  description = "EKS 클러스터명 (서브넷 태그용, network가 eks보다 먼저 생성되므로 이름만 문자열로 전달)"
  type        = string
}

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "azs" {
  type    = list(string)
  default = ["ap-northeast-2a", "ap-northeast-2c"]
}

variable "public_subnet_cidrs" {
  type    = list(string)
  default = ["10.0.0.0/24", "10.0.1.0/24"]
}

variable "private_subnet_cidrs" {
  description = "EKS 워커 노드 / 파드용. VPC CNI가 IP를 대량 소비하므로 여유 대역 확보"
  type        = list(string)
  default     = ["10.0.10.0/24", "10.0.11.0/24"]
}

variable "database_subnet_cidrs" {
  description = "RDS 전용. 최소 2개 AZ 필수(DB Subnet Group 제약)"
  type        = list(string)
  default     = ["10.0.20.0/24", "10.0.21.0/24"]
}

variable "common_tags" {
  type    = map(string)
  default = {}
}
