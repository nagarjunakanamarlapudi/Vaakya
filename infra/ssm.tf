# =============================================================================
# Vaakya Infrastructure — SSM Parameter Store
# =============================================================================
#
# SSM Parameter Store instead of Secrets Manager ($0 for standard params
# vs $0.40/secret/month). Lambda reads SecureString params at runtime
# via the SDK.

# --- Secrets (SecureString) --------------------------------------------------

resource "aws_ssm_parameter" "jwt_secret" {
  name        = "/vaakya/${var.stage}/jwt-secret"
  type        = "SecureString"
  value       = var.jwt_secret
  description = "JWT signing key for auth tokens"

  tags = { Name = "vaakya-jwt-secret-${var.stage}" }
}

resource "aws_ssm_parameter" "share_secret" {
  name        = "/vaakya/${var.stage}/share-secret"
  type        = "SecureString"
  value       = var.share_secret != "" ? var.share_secret : "placeholder"
  description = "JWT signing key for share link tokens"

  tags = { Name = "vaakya-share-secret-${var.stage}" }
}

resource "aws_ssm_parameter" "apple_team_id" {
  name        = "/vaakya/${var.stage}/apple-team-id"
  type        = "SecureString"
  value       = var.apple_team_id != "" ? var.apple_team_id : "placeholder"
  description = "Apple Developer Team ID"

  tags = { Name = "vaakya-apple-team-id-${var.stage}" }
}

resource "aws_ssm_parameter" "apple_key_id" {
  name        = "/vaakya/${var.stage}/apple-key-id"
  type        = "SecureString"
  value       = var.apple_key_id != "" ? var.apple_key_id : "placeholder"
  description = "Apple Sign-In key ID"

  tags = { Name = "vaakya-apple-key-id-${var.stage}" }
}

resource "aws_ssm_parameter" "apple_private_key" {
  name        = "/vaakya/${var.stage}/apple-private-key"
  type        = "SecureString"
  value       = var.apple_private_key != "" ? var.apple_private_key : "placeholder"
  description = "Apple Sign-In private key (PEM)"

  tags = { Name = "vaakya-apple-private-key-${var.stage}" }
}

resource "aws_ssm_parameter" "apple_client_id" {
  name        = "/vaakya/${var.stage}/apple-client-id"
  type        = "SecureString"
  value       = var.apple_client_id != "" ? var.apple_client_id : "placeholder"
  description = "Apple Sign-In client (service) ID"

  tags = { Name = "vaakya-apple-client-id-${var.stage}" }
}

resource "aws_ssm_parameter" "google_client_id" {
  name        = "/vaakya/${var.stage}/google-client-id"
  type        = "SecureString"
  value       = var.google_client_id != "" ? var.google_client_id : "placeholder"
  description = "Google OAuth client ID"

  tags = { Name = "vaakya-google-client-id-${var.stage}" }
}

# --- Runtime config (String) ------------------------------------------------

resource "aws_ssm_parameter" "ai_provider" {
  name        = "/vaakya/${var.stage}/ai-provider"
  type        = "String"
  value       = "anthropic"
  description = "Default Platform AI provider (anthropic/openai)"

  tags = { Name = "vaakya-ai-provider-${var.stage}" }
}
