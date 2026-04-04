# =============================================================================
# Vaakya Infrastructure — Outputs
# =============================================================================

output "api_url" {
  value       = aws_apigatewayv2_api.api.api_endpoint
  description = "API Gateway HTTP API endpoint URL"
}

output "lambda_arn" {
  value       = aws_lambda_function.api.arn
  description = "Lambda function ARN"
}

output "ecr_repository" {
  value       = aws_ecr_repository.api.repository_url
  description = "ECR repository URL for docker push"
}

output "data_bucket" {
  value       = aws_s3_bucket.data.id
  description = "S3 bucket for user meetings and audio"
}

output "share_bucket" {
  value       = aws_s3_bucket.share.id
  description = "S3 bucket for share viewer SPA"
}

output "share_url" {
  value       = aws_cloudfront_distribution.share.domain_name
  description = "CloudFront domain for share viewer"
}

output "cloudfront_distribution_id" {
  value       = aws_cloudfront_distribution.share.id
  description = "CloudFront distribution ID (for cache invalidation)"
}
