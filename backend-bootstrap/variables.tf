variable "aws_region" {
  type    = string
  default = "ap-northeast-2"
}

variable "state_bucket_name" {
  description = "전역 유일 버킷명. 실제 값으로 변경 후 apply"
  type        = string
  default     = "hybrid-toy-tfstate-kuspital"
}
