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

variable "jwt_secret" {
  type        = string
  sensitive   = true
  description = "JWT signing key for auth tokens"
}

variable "share_secret" {
  type        = string
  sensitive   = true
  default     = ""
  description = "JWT signing key for share link tokens"
}

variable "apple_team_id" {
  type        = string
  default     = ""
  description = "Apple Developer Team ID for Sign in with Apple"
}

variable "apple_key_id" {
  type        = string
  default     = ""
  description = "Apple Sign-In key ID"
}

variable "apple_private_key" {
  type        = string
  sensitive   = true
  default     = ""
  description = "Apple Sign-In private key (PEM)"
}

variable "apple_client_id" {
  type        = string
  default     = ""
  description = "Apple Sign-In client (service) ID"
}

variable "google_client_id" {
  type        = string
  default     = ""
  description = "Google OAuth client ID"
}

variable "domain" {
  type        = string
  default     = "vaakya.app"
  description = "Root domain for Vaakya services"
}
