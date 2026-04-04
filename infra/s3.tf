# =============================================================================
# Vaakya Infrastructure — S3 Buckets
# =============================================================================

# --- Data bucket (private, for user meetings + audio) -----------------------

resource "aws_s3_bucket" "data" {
  bucket = "vaakya-data-${var.stage}"
}

resource "aws_s3_bucket_public_access_block" "data" {
  bucket = aws_s3_bucket.data.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "data" {
  bucket = aws_s3_bucket.data.id

  rule {
    id     = "transition-audio-to-ia"
    status = "Enabled"

    filter {
      prefix = "users/"
    }

    transition {
      days          = 90
      storage_class = "STANDARD_IA"
    }
  }
}

# --- Share viewer bucket (served via CloudFront) -----------------------------

resource "aws_s3_bucket" "share" {
  bucket = "vaakya-share-${var.stage}"
}

resource "aws_s3_bucket_public_access_block" "share" {
  bucket = aws_s3_bucket.share.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_policy" "share" {
  bucket = aws_s3_bucket.share.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowCloudFrontOAC"
      Effect    = "Allow"
      Principal = { Service = "cloudfront.amazonaws.com" }
      Action    = "s3:GetObject"
      Resource  = "${aws_s3_bucket.share.arn}/*"
      Condition = {
        StringEquals = {
          "AWS:SourceArn" = aws_cloudfront_distribution.share.arn
        }
      }
    }]
  })
}
