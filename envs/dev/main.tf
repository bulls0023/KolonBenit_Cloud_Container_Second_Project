locals {
  common_tags = {
    Project     = var.project_name
    Environment = "dev"
    ManagedBy   = "terraform"
  }
}

module "network" {
  source = "../../modules/network"

  project_name = var.project_name
  cluster_name = "${var.project_name}-eks"
  common_tags  = local.common_tags
}

module "eks" {
  source = "../../modules/eks"

  cluster_name       = "${var.project_name}-eks"
  vpc_id             = module.network.vpc_id
  private_subnet_ids = module.network.private_subnet_ids # EKS 워커 전용, DB 서브넷 미포함
  common_tags        = local.common_tags

  developer_iam_arns = {
    web = "arn:aws:iam::597106152264:user/kusbff"
    bff = "arn:aws:iam::597106152264:user/kusweb"
    was = "arn:aws:iam::597106152264:user/kuswas"
    db  = "arn:aws:iam::597106152264:user/kusdb"
  }
}

module "ecr" {
  source = "../../modules/ecr"

  project_name = var.project_name
}

module "rds" {
  source = "../../modules/rds"

  project_name               = var.project_name
  vpc_id                     = module.network.vpc_id
  database_subnet_ids        = module.network.database_subnet_ids
  eks_node_security_group_id = module.eks.node_security_group_id
  common_tags                = local.common_tags
}

# --- ALB 진입점용 ACM 인증서 ---
# 도메인 검증(CNAME)은 Cloudflare 대시보드에서 수동 추가 (조건 3)
resource "aws_acm_certificate" "alb" {
  domain_name       = var.alb_domain_name
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = local.common_tags
}


