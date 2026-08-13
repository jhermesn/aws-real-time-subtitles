module "sign_room" {
  source  = "terraform-aws-modules/lambda/aws"
  version = "~> 7.0"

  function_name = "${var.prefix}-sign-room"
  description   = "Signs speaker room tokens; reachable only via CloudFront (OAC-signed origin)"
  handler       = "index.handler"
  runtime       = "nodejs20.x"
  source_path   = "${path.module}/lambda/sign-room"

  environment_variables = {
    SIGNING_SECRET           = var.signing_secret
    SPEAKER_SESSION_ROLE_ARN = module.speaker_session_role.arn
  }

  create_role                       = false
  lambda_role                       = module.lambda_exec_role.arn
  cloudwatch_logs_retention_in_days = 30
  # No reserved_concurrent_executions: AWS requires at least 10 unreserved
  # concurrent executions per account, and small/new accounts can start with
  # an account-wide limit as low as 10 total, leaving no room to reserve any.

  create_lambda_function_url = true
  authorization_type         = "AWS_IAM"

  # OAC signs every CloudFront-forwarded request with the distribution's own
  # identity, scoped by source_arn below: no shared secret to leak, no
  # principal = "*" to abuse. Since October 2025 AWS requires both
  # lambda:InvokeFunctionUrl and lambda:InvokeFunction for Function URL access.
  # The Function URL is unqualified ($LATEST), so only the unqualified-alias
  # trigger permissions are needed.
  create_current_version_allowed_triggers = false
  allowed_triggers = {
    CloudFrontInvokeFunctionUrl = {
      action                 = "lambda:InvokeFunctionUrl"
      principal              = "cloudfront.amazonaws.com"
      source_arn             = module.cloudfront.cloudfront_distribution_arn
      function_url_auth_type = "AWS_IAM"
    }
    CloudFrontInvokeFunction = {
      action     = "lambda:InvokeFunction"
      principal  = "cloudfront.amazonaws.com"
      source_arn = module.cloudfront.cloudfront_distribution_arn
    }
  }
}
