module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "${var.project_name}-vpc"
  cidr = var.vpc_cidr

  azs = var.azs

  # 3-tier 서브넷 분리
  public_subnets   = var.public_subnet_cidrs   # ALB
  private_subnets  = var.private_subnet_cidrs  # EKS 워커 노드 / 파드
  database_subnets = var.database_subnet_cidrs # RDS 전용

  enable_nat_gateway   = true
  single_nat_gateway   = true # 토이 프로젝트 -> 비용 절감, AZ당 NAT 아님
  enable_dns_hostnames = true
  enable_dns_support   = true

  # DB 서브넷 그룹은 modules/rds 에서 직접 생성 -> 여기서는 중복 생성 방지
  create_database_subnet_route_table = true
  create_database_subnet_group = false
  # DB 서브넷은 NAT 경로 없음(모듈 기본값) -> 아웃바운드 인터넷 차단 상태 유지

  # EKS가 서브넷을 인식하기 위한 필수 태그
  public_subnet_tags = {
    "kubernetes.io/role/elb"                    = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb"           = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }

  # DB 서브넷에는 kubernetes.io 태그를 넣지 않는다.
  # 태그가 있으면 LB Controller가 ELB 배치 후보로 인식할 수 있음.
  database_subnet_tags = {
    Tier = "database"
  }

  tags = var.common_tags
}
