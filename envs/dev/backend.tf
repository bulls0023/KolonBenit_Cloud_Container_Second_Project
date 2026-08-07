terraform {
  backend "s3" {
    bucket       = "hybrid-toy-tfstate-kuspital" # backend-bootstrap output 값과 일치시킬 것
    key          = "envs/dev/terraform.tfstate"
    region       = "ap-northeast-2"
    encrypt      = true
    use_lockfile = true # Terraform >= 1.10 S3 native locking, DynamoDB 불필요
  }
}
