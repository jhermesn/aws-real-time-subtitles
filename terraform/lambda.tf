module "sign_room" {
  source  = "terraform-aws-modules/lambda/aws"
  version = "~> 7.0"

  function_name = "${var.prefix}-sign-room"
  description   = "Signs speaker room tokens; invoked only via CloudFront OAC"
  handler       = "index.handler"
  runtime       = "nodejs20.x"
  source_path   = "${path.module}/lambda/sign-room"

  environment_variables = {
    SIGNING_SECRET = var.signing_secret
  }

  create_role                       = false
  lambda_role                       = aws_iam_role.lambda_exec.arn
  cloudwatch_logs_retention_in_days = 30
}

resource "aws_lambda_function_url" "sign_room" {
  function_name      = module.sign_room.lambda_function_name
  authorization_type = "AWS_IAM"
}

# Allow CloudFront (via OAC) to invoke the function URL
resource "aws_lambda_permission" "cloudfront" {
  statement_id           = "AllowCloudFrontOAC"
  action                 = "lambda:InvokeFunctionUrl"
  function_name          = module.sign_room.lambda_function_name
  principal              = "cloudfront.amazonaws.com"
  source_arn             = module.cloudfront.cloudfront_distribution_arn
  function_url_auth_type = "AWS_IAM"
}
