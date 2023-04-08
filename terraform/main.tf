# comment
locals {

  web_bucket_base_name = "${var.app_name}-${terraform.workspace}-web"

  app_domain = terraform.workspace == "main" ? var.root_domain : join(".", [
    terraform.workspace, var.root_domain
  ])
  api_domain = "api.${local.app_domain}"
}

resource "aws_s3_account_public_access_block" "global" {
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Primary is our initial region - us-east-2.

resource "aws_s3_bucket" "web-primary" {
  bucket = "${local.web_bucket_base_name}-primary"
}

resource "aws_s3_bucket_policy" "web-primary" {
  bucket = aws_s3_bucket.web-primary.bucket
  policy = data.aws_iam_policy_document.web-primary.json
}

resource "aws_s3_bucket_website_configuration" "web-primary" {
  bucket = aws_s3_bucket.web-primary.bucket
  index_document {
    suffix = "index.html"
  }
  error_document {
    key = "error.html"
  }
}

resource "aws_s3_bucket_versioning" "web-primary" {
  bucket = aws_s3_bucket.web-primary.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "web-primary" {
  bucket = aws_s3_bucket.web-primary.bucket
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "web-primary" {
  bucket = aws_s3_bucket.web-primary.bucket
  rule {
    id     = "${terraform.workspace}-web-primary-lifecycle"
    status = "Enabled"
    noncurrent_version_expiration {
      noncurrent_days = 7
    }
  }
}

resource "aws_s3_bucket_public_access_block" "web-primary" {
  bucket                  = aws_s3_bucket.web-primary.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

data "aws_iam_policy_document" "web-primary" {
  statement {
    principals {
      type        = "AWS"
      identifiers = [aws_cloudfront_origin_access_identity.web-oai.iam_arn]
    }
    actions = [
      "s3:GetObject",
      "s3:GetObjectVersion"
    ]
    resources = [
      aws_s3_bucket.web-primary.arn,
      "${aws_s3_bucket.web-primary.arn}/*"
    ]
  }
}

# Secondary is us-east-1 (Virginia) - this is our failover origin

resource "aws_s3_bucket" "web-logs" {
  provider = aws.us-east-1
  bucket   = "${local.web_bucket_base_name}-logs"
}

resource "aws_s3_bucket_acl" "web-logs" {
  provider = aws.us-east-1
  bucket   = aws_s3_bucket.web-logs.bucket
  acl      = "private"
}

resource "aws_s3_bucket_server_side_encryption_configuration" "web-logs" {
  provider = aws.us-east-1
  bucket   = aws_s3_bucket.web-logs.bucket
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "web-logs" {
  provider                = aws.us-east-1
  bucket                  = aws_s3_bucket.web-logs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "web-logs" {
  provider = aws.us-east-1
  bucket   = aws_s3_bucket.web-logs.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "web-logs" {
  provider = aws.us-east-1
  bucket   = aws_s3_bucket.web-logs.bucket
  rule {
    id     = "${terraform.workspace}-web-log-lifecycle"
    status = "Enabled"
    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }
    noncurrent_version_expiration {
      noncurrent_days = 7
    }
    expiration {
      days = 60
    }
  }
}

resource "aws_cloudfront_origin_access_identity" "web-oai" {
  provider = aws.us-east-1
  comment  = "Managed by ${var.app_name}-${terraform.workspace} terraform"
}

resource "aws_cloudfront_distribution" "web-dist" {
  provider            = aws.us-east-1
  depends_on          = [aws_acm_certificate.web-cert]
  price_class         = "PriceClass_100"
  enabled             = true
  default_root_object = "index.html"

  aliases = [local.app_domain, join(".", ["www", local.app_domain])]

  custom_error_response {
    error_code            = 404
    response_code         = 200
    response_page_path    = "/index.html"
    error_caching_min_ttl = 30
  }
  custom_error_response {
    error_code            = 403
    response_code         = 200
    response_page_path    = "/index.html"
    error_caching_min_ttl = 30
  }

  default_cache_behavior {
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["HEAD", "GET", "OPTIONS"]
    target_origin_id       = "groupS3"
    compress               = true
    viewer_protocol_policy = "redirect-to-https"
    forwarded_values {
      query_string = false
      cookies {
        forward = "all"
      }
    }
    min_ttl     = 0
    default_ttl = 3600
    max_ttl     = 86400
  }

#  origin_group {
#    origin_id = "groupS3"
#    failover_criteria {
#      status_codes = [500, 502]
#    }
#    member {
#      origin_id = "primaryS3"
#    }
#  }

  origin {
    domain_name = aws_s3_bucket.web-primary.bucket_regional_domain_name
    origin_id   = "primaryS3"

    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.web-oai.cloudfront_access_identity_path
    }
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = false
    acm_certificate_arn            = aws_acm_certificate.web-cert.arn
    ssl_support_method             = "sni-only"
    minimum_protocol_version       = "TLSv1.2_2019"
  }
}

resource "aws_acm_certificate" "web-cert" {
  provider                  = aws.us-east-1
  domain_name               = local.app_domain
  subject_alternative_names = [join(".", ["*", local.app_domain])]
  validation_method         = "DNS"
  lifecycle {
    create_before_destroy = true
  }
  tags = {
    Name = "${var.app_name} - ${terraform.workspace}"
  }
}