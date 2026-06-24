output "app_url" {
  description = "CloudFront URL for the application"
  value       = "https://${module.cloudfront.cloudfront_distribution_domain_name}"
}

output "cognito_identity_pool_id" {
  description = "Cognito Identity Pool ID, injected into React bundle at build time"
  value       = aws_cognito_identity_pool.main.id
}

output "aws_region" {
  description = "AWS region, injected into React bundle at build time"
  value       = var.aws_region
}

output "s3_bucket_name" {
  description = "S3 bucket for deploying React build artifacts"
  value       = module.s3_bucket.s3_bucket_id
}

output "cloudfront_distribution_id" {
  description = "CloudFront distribution ID for cache invalidation"
  value       = module.cloudfront.cloudfront_distribution_id
}
