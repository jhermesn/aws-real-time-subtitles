data "aws_caller_identity" "current" {}

module "lambda_exec_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role"
  version = "~> 6.0"

  name            = "${var.prefix}-lambda-exec"
  use_name_prefix = false

  trust_policy_permissions = {
    LambdaService = {
      actions = ["sts:AssumeRole"]
      principals = [{
        type        = "Service"
        identifiers = ["lambda.amazonaws.com"]
      }]
    }
  }

  policies = {
    AWSLambdaBasicExecutionRole = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
  }
}

# Assumed by lambda_exec on every GET /api/session call to vend a short-lived
# session credential to the speaker's browser. Trust is scoped to lambda_exec
# only; no other principal in the account can assume this role.
module "speaker_session_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role"
  version = "~> 6.0"

  name                 = "${var.prefix}-speaker-session"
  use_name_prefix      = false
  max_session_duration = 3600

  trust_policy_permissions = {
    LambdaExecAssume = {
      actions = ["sts:AssumeRole"]
      principals = [{
        type        = "AWS"
        identifiers = [module.lambda_exec_role.arn]
      }]
    }
  }

  create_inline_policy = true
  inline_policy_permissions = {
    TranscribeStreaming = {
      actions   = ["transcribe:StartStreamTranscription", "transcribe:StartStreamTranscriptionWebSocket"]
      resources = ["*"] # Transcribe streaming actions do not support resource-level restrictions
      condition = [{ test = "StringEquals", variable = "aws:RequestedRegion", values = [var.aws_region] }]
    }
    Translate = {
      actions   = ["translate:TranslateText"]
      resources = ["*"] # translate:TranslateText does not support resource-level restrictions
      condition = [{ test = "StringEquals", variable = "aws:RequestedRegion", values = [var.aws_region] }]
    }
  }
}

# Cross-role trust: lambda_exec needs permission to assume speaker_session,
# and speaker_session's trust policy needs lambda_exec's ARN. Neither
# per-role module call can express both sides without a cycle, so this one
# statement is a standalone resource instead of folded into either module.
resource "aws_iam_role_policy" "lambda_assume_speaker_session" {
  name = "${var.prefix}-lambda-assume-speaker-session"
  role = module.lambda_exec_role.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "sts:AssumeRole"
      Resource = module.speaker_session_role.arn
    }]
  })
}
