# =============================================================================
# Vaakya Infrastructure — Route 53 DNS + ACM Certificates
# =============================================================================
#
# Assumes the hosted zone for the domain already exists. If not, create it
# manually first:
#   aws route53 create-hosted-zone --name vaakya.app --caller-reference $(date +%s)

data "aws_route53_zone" "main" {
  count = var.stage == "prod" ? 1 : 0
  name  = var.domain
}

# --- ACM Certificates -------------------------------------------------------

# Certificate for API (api.vaakya.app)
resource "aws_acm_certificate" "api" {
  count             = var.stage == "prod" ? 1 : 0
  domain_name       = "api.${var.domain}"
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name = "vaakya-api-cert"
  }
}

resource "aws_route53_record" "api_cert_validation" {
  for_each = var.stage == "prod" ? {
    for dvo in aws_acm_certificate.api[0].domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  } : {}

  zone_id = data.aws_route53_zone.main[0].zone_id
  name    = each.value.name
  type    = each.value.type
  ttl     = 300
  records = [each.value.record]
}

resource "aws_acm_certificate_validation" "api" {
  count                   = var.stage == "prod" ? 1 : 0
  certificate_arn         = aws_acm_certificate.api[0].arn
  validation_record_fqdns = [for record in aws_route53_record.api_cert_validation : record.fqdn]
}

# Certificate for share viewer (share.vaakya.app)
# Must be in us-east-1 for CloudFront
resource "aws_acm_certificate" "share" {
  count             = var.stage == "prod" ? 1 : 0
  domain_name       = "share.${var.domain}"
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name = "vaakya-share-cert"
  }
}

resource "aws_route53_record" "share_cert_validation" {
  for_each = var.stage == "prod" ? {
    for dvo in aws_acm_certificate.share[0].domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  } : {}

  zone_id = data.aws_route53_zone.main[0].zone_id
  name    = each.value.name
  type    = each.value.type
  ttl     = 300
  records = [each.value.record]
}

resource "aws_acm_certificate_validation" "share" {
  count                   = var.stage == "prod" ? 1 : 0
  certificate_arn         = aws_acm_certificate.share[0].arn
  validation_record_fqdns = [for record in aws_route53_record.share_cert_validation : record.fqdn]
}

# --- DNS Records -------------------------------------------------------------

# API -> API Gateway
resource "aws_route53_record" "api" {
  count   = var.stage == "prod" ? 1 : 0
  zone_id = data.aws_route53_zone.main[0].zone_id
  name    = "api.${var.domain}"
  type    = "CNAME"
  ttl     = 300
  records = [replace(aws_apigatewayv2_api.api.api_endpoint, "https://", "")]
}

# Share viewer -> CloudFront
resource "aws_route53_record" "share" {
  count   = var.stage == "prod" ? 1 : 0
  zone_id = data.aws_route53_zone.main[0].zone_id
  name    = "share.${var.domain}"
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.share.domain_name
    zone_id                = aws_cloudfront_distribution.share.hosted_zone_id
    evaluate_target_health = false
  }
}
