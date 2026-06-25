module "sign_room" {
  source  = "terraform-aws-modules/lambda/aws"
  version = "~> 7.0"

  function_name = "${var.prefix}-sign-room"
  description   = "Signs speaker room tokens; reachable only via CloudFront (WAF IP-allowlisted)"
  handler       = "index.handler"
  runtime       = "nodejs20.x"
  source_path   = "${path.module}/lambda/sign-room"

  environment_variables = {
    SIGNING_SECRET   = var.signing_secret
    CF_ORIGIN_SECRET = var.cloudfront_origin_secret
  }

  create_role                       = false
  lambda_role                       = aws_iam_role.lambda_exec.arn
  cloudwatch_logs_retention_in_days = 30
}

resource "aws_lambda_function_url" "sign_room" {
  function_name      = module.sign_room.lambda_function_name
  authorization_type = "NONE"
}
