# =============================================================================
# Vaakya Infrastructure — Input Variables
# =============================================================================

variable "stage" {
  type        = string
  description = "Environment stage (dev, stg, prod)"

  validation {
    condition     = contains(["dev", "stg", "prod"], var.stage)
    error_message = "Stage must be one of: dev, stg, prod."
  }
}

variable "aws_region" {
  type        = string
  default     = "us-east-1"
  description = "AWS region for all resources"
}

variable "share_secret" {
  type        = string
  sensitive   = true
  default     = ""
  description = "JWT signing key for share link tokens"
}

variable "firebase_project_id" {
  type        = string
  default     = "vaakya-a5abf"
  description = "Firebase project ID for JWT authorizer"
}

variable "domain" {
  type        = string
  default     = "vaakya.app"
  description = "Root domain for Vaakya services"
}
