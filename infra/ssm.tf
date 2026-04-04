# =============================================================================
# Vaakya Infrastructure — SSM Parameter Store
# =============================================================================
#
# SSM Parameter Store instead of Secrets Manager ($0 for standard params
# vs $0.40/secret/month). Lambda reads SecureString params at runtime
# via the SDK.

# --- Secrets (SecureString) --------------------------------------------------

resource "aws_ssm_parameter" "share_secret" {
  name        = "/vaakya/${var.stage}/share-secret"
  type        = "SecureString"
  value       = var.share_secret != "" ? var.share_secret : "placeholder"
  description = "JWT signing key for share link tokens"

  tags = { Name = "vaakya-share-secret-${var.stage}" }
}

# --- Runtime config (String) ------------------------------------------------

resource "aws_ssm_parameter" "ai_provider" {
  name        = "/vaakya/${var.stage}/ai-provider"
  type        = "String"
  value       = "anthropic"
  description = "Default Platform AI provider (anthropic/openai)"

  tags = { Name = "vaakya-ai-provider-${var.stage}" }
}
