variable "aws_region" {
  type    = string
  default = "ap-northeast-2"
}

variable "project_name" {
  type    = string
  default = "hybrid-toy"
}

variable "alb_domain_name" {
  description = "ALB 앞단 ACM 인증서 발급 대상 도메인 (Cloudflare 관리 도메인)"
  type        = string
}
