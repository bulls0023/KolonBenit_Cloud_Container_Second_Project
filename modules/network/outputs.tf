output "vpc_id" {
  value = module.vpc.vpc_id
}

output "public_subnet_ids" {
  value = module.vpc.public_subnets
}

output "private_subnet_ids" {
  description = "EKS 워커 노드 배치용"
  value       = module.vpc.private_subnets
}

output "database_subnet_ids" {
  description = "RDS 전용"
  value       = module.vpc.database_subnets
}

output "database_subnet_cidrs" {
  value = module.vpc.database_subnets_cidr_blocks
}
