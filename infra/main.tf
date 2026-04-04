# =============================================================================
# Vaakya Infrastructure — Provider & Backend
# =============================================================================

terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Remote state in S3 — separate state file per stage.
  # The "key" is overridden per stage via -backend-config in Makefile:
  #   stg  → infra/stg/terraform.tfstate
  #   prod → infra/prod/terraform.tfstate
  #
  # Create bucket once:
  #   aws s3api create-bucket --bucket vaakya-terraform-state --region us-east-1
  #   aws s3api put-bucket-versioning --bucket vaakya-terraform-state \
  #       --versioning-configuration Status=Enabled
  backend "s3" {
    bucket = "vaakya-terraform-state"
    key    = "infra/default/terraform.tfstate"  # overridden by -backend-config
    region = "us-east-1"
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project   = "vaakya"
      Stage     = var.stage
      ManagedBy = "terraform"
    }
  }
}
