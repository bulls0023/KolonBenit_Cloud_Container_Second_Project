output "eks_cluster_name" {
  value = module.eks.cluster_name
}

output "eks_cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "ecr_repository_urls" {
  value = module.ecr.repository_urls
}

output "rds_endpoint" {
  value = module.rds.endpoint
}

output "acm_certificate_arn" {
  value = aws_acm_certificate.alb.arn
}

output "kubeconfig_update_cmd" {
  description = "EKS팀 즉시 접속용 명령어"
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${module.eks.cluster_name}"
}

output "rds_master_secret_arn" {
  value = module.rds.db_instance_master_user_secret_arn
}

output "lbc_irsa_role_arn" {
  description = "LB Controller Helm 설치 시 사용"
  value       = module.eks.lbc_irsa_role_arn
}