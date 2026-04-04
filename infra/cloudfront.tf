# =============================================================================
# Vaakya Infrastructure — CloudFront (Share Viewer CDN)
# =============================================================================

resource "aws_cloudfront_origin_access_control" "share" {
  name                              = "vaakya-share-${var.stage}"
  description                       = "OAC for share viewer S3 bucket"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_distribution" "share" {
  enabled             = true
  default_root_object = "index.html"
  comment             = "Vaakya share viewer (${var.stage})"

  aliases = var.stage == "prod" ? ["share.${var.domain}"] : []

  origin {
    domain_name              = aws_s3_bucket.share.bucket_regional_domain_name
    origin_id                = "s3-share"
    origin_access_control_id = aws_cloudfront_origin_access_control.share.id
  }

  default_cache_behavior {
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "s3-share"
    viewer_protocol_policy = "redirect-to-https"

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    min_ttl     = 0
    default_ttl = 3600
    max_ttl     = 86400
  }

  # SPA routing: 404 -> /index.html
  custom_error_response {
    error_code            = 403
    response_code         = 200
    response_page_path    = "/index.html"
    error_caching_min_ttl = 10
  }

  custom_error_response {
    error_code            = 404
    response_code         = 200
    response_page_path    = "/index.html"
    error_caching_min_ttl = 10
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    # Use ACM cert for prod; default CloudFront cert for dev/stg
    acm_certificate_arn            = var.stage == "prod" ? aws_acm_certificate.share[0].arn : null
    ssl_support_method             = var.stage == "prod" ? "sni-only" : null
    cloudfront_default_certificate = var.stage != "prod"
  }

  tags = {
    Name = "vaakya-share-${var.stage}"
  }
}
