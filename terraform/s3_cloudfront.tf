locals {
  lambda_url_host = trimsuffix(trimprefix(aws_lambda_function_url.sign_room.function_url, "https://"), "/")
}

module "s3_bucket" {
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "~> 4.0"

  bucket = "${var.prefix}-app-${data.aws_caller_identity.current.account_id}"

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true

  versioning = {
    enabled = true
  }

  server_side_encryption_configuration = {
    rule = {
      apply_server_side_encryption_by_default = {
        sse_algorithm = "AES256"
      }
    }
  }
}

resource "aws_cloudfront_function" "speaker_auth" {
  name    = "${var.prefix}-speaker-auth"
  runtime = "cloudfront-js-2.0"
  publish = true
  code    = templatefile("${path.module}/cloudfront-functions/speaker-auth.js.tpl", {
    signing_secret  = var.signing_secret
    admin_ips       = var.admin_ips
    admin_ips_v6    = var.admin_ips_v6
  })
}

module "cloudfront" {
  source  = "terraform-aws-modules/cloudfront/aws"
  version = "~> 3.4"

  comment             = "${var.prefix} real-time subtitles"
  enabled             = true
  is_ipv6_enabled     = true
  price_class         = "PriceClass_100"
  http_version        = "http2and3"
  retain_on_delete    = false
  wait_for_deployment = true

  web_acl_id = aws_wafv2_web_acl.main.arn

  create_origin_access_control = true
  origin_access_control = {
    s3_oac = {
      description      = "${var.prefix} S3 OAC"
      origin_type      = "s3"
      signing_behavior = "always"
      signing_protocol = "sigv4"
    }
  }

  origin = {
    s3 = {
      domain_name           = module.s3_bucket.s3_bucket_bucket_regional_domain_name
      origin_access_control = "s3_oac"
    }
    lambda = {
      domain_name = local.lambda_url_host
      # CloudFront overrides any viewer-sent X-CF-Secret with this value,
      # so it cannot be forged by callers who know the Lambda URL directly.
      custom_header = [
        { name = "X-CF-Secret", value = var.cloudfront_origin_secret }
      ]
      custom_origin_config = {
        http_port              = 80
        https_port             = 443
        origin_protocol_policy = "https-only"
        origin_ssl_protocols   = ["TLSv1.2"]
      }
    }
  }

  default_cache_behavior = {
    target_origin_id       = "s3"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true
    use_forwarded_values   = false
    cache_policy_id        = "658327ea-f89d-4fab-a63d-7e88639e58f6" # CachingOptimized

    function_association = {
      viewer-request = {
        function_arn = aws_cloudfront_function.speaker_auth.arn
      }
    }
  }

  ordered_cache_behavior = [
    {
      path_pattern             = "/api/*"
      target_origin_id         = "lambda"
      viewer_protocol_policy   = "https-only"
      allowed_methods          = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
      cached_methods           = ["GET", "HEAD"]
      compress                 = false
      use_forwarded_values     = false
      cache_policy_id          = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad" # CachingDisabled
      origin_request_policy_id = "b689b0a8-53d0-40ab-baf2-68738e2966ac" # AllViewerExceptHostHeader
    }
  ]

  custom_error_response = [
    {
      error_code            = 403
      response_code         = 200
      response_page_path    = "/index.html"
      error_caching_min_ttl = 10
    },
    {
      error_code            = 404
      response_code         = 200
      response_page_path    = "/index.html"
      error_caching_min_ttl = 10
    }
  ]
}

resource "aws_s3_bucket_policy" "app" {
  bucket = module.s3_bucket.s3_bucket_id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "cloudfront.amazonaws.com" }
      Action    = "s3:GetObject"
      Resource  = "${module.s3_bucket.s3_bucket_arn}/*"
      Condition = {
        StringEquals = {
          "AWS:SourceArn" = module.cloudfront.cloudfront_distribution_arn
        }
      }
    }]
  })
}
