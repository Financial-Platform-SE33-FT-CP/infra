# ============================================================
# 会计平台 — Terraform 基础设施
# 用于在 AWS 上部署完整环境
# ============================================================

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  backend "s3" {
    bucket = "accounting-platform-terraform-state"
    key    = "infrastructure/terraform.tfstate"
    region = "ap-southeast-1"
    encrypt = true
  }
}

provider "aws" {
  region = var.aws_region
  default_tags {
    tags = {
      Project     = "accounting-platform"
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}

module "vpc" {
  source = "./modules/vpc"

  vpc_cidr           = var.vpc_cidr
  availability_zones = var.availability_zones
  environment        = var.environment
}

module "eks" {
  source = "./modules/eks"

  cluster_name       = var.cluster_name
  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids
  environment        = var.environment
  node_instance_types = var.node_instance_types
  min_nodes          = var.min_nodes
  max_nodes          = var.max_nodes
}

module "rds" {
  source = "./modules/rds"

  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids
  environment        = var.environment
  db_username        = var.db_username
  db_password        = var.db_password
  allowed_security_groups = [module.eks.node_security_group_id]
}

module "elasticache" {
  source = "./modules/elasticache"

  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids
  environment        = var.environment
  allowed_security_groups = [module.eks.node_security_group_id]
}
