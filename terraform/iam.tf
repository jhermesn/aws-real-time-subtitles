data "aws_caller_identity" "current" {}

resource "aws_iam_role" "cognito_unauth" {
  name = "${var.prefix}-cognito-unauth"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = "cognito-identity.amazonaws.com" }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "cognito-identity.amazonaws.com:aud" = aws_cognito_identity_pool.main.id
        }
        "ForAnyValue:StringLike" = {
          "cognito-identity.amazonaws.com:amr" = "unauthenticated"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy" "cognito_unauth" {
  name = "${var.prefix}-cognito-unauth"
  role = aws_iam_role.cognito_unauth.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = [
          "transcribe:StartStreamTranscription",
          "transcribe:StartStreamTranscriptionWebSocket",
        ]
        Resource = "*" # Transcribe streaming actions do not support resource-level restrictions
      },
      {
        Effect   = "Allow"
        Action   = "translate:TranslateText"
        Resource = "*" # translate:TranslateText does not support resource-level restrictions
      }
    ]
  })
}

resource "aws_iam_role" "lambda_exec" {
  name = "${var.prefix}-lambda-exec"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}
