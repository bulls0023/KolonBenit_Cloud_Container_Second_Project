terraform {
  required_version = ">= 1.10.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
  # 이 디렉토리는 부트스트랩 전용 -> local state 유지 (닭-달걀 문제 회피)
}

provider "aws" {
  region = var.aws_region
}

resource "aws_s3_bucket" "tf_state" {
  bucket = var.state_bucket_name

  # 실수로 destroy 되는 것 방지
  lifecycle {
    prevent_destroy = true
  }
}

# 필수 옵션 1: 버전관리 (상태 파일 롤백/복구용)
resource "aws_s3_bucket_versioning" "tf_state" {
  bucket = aws_s3_bucket.tf_state.id
  versioning_configuration {
    status = "Enabled"
  }
}

# 필수 옵션 2: 기본 암호화 (SSE-S3)
resource "aws_s3_bucket_server_side_encryption_configuration" "tf_state" {
  bucket = aws_s3_bucket.tf_state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# 필수 옵션 3: 퍼블릭 액세스 완전 차단
resource "aws_s3_bucket_public_access_block" "tf_state" {
  bucket                  = aws_s3_bucket.tf_state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# NOTE: DynamoDB lock table 미사용.
# Terraform >= 1.10 부터 S3 backend 자체 native locking(use_lockfile) 지원 -> 별도 인프라 불필요.
# 단, 동시 apply 경쟁이 사실상 없는 구조(관리자 1인 apply)이므로 최소 구성으로 충분.
