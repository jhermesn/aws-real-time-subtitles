terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  # Local backend, state lives in terraform/bootstrap/terraform.tfstate
  # Commit it or keep it in CloudShell $HOME (persists across sessions per region)
}

provider "aws" {
  region = var.aws_region
}

data "aws_caller_identity" "current" {}

locals {
  account_id    = data.aws_caller_identity.current.account_id
  state_bucket  = "${var.prefix}-tfstate-${local.account_id}"
  lock_table    = "${var.prefix}-tflock"
  role_name     = "${var.prefix}-github-actions"
  oidc_provider_arn = (
    var.create_oidc_provider
    ? aws_iam_openid_connect_provider.github[0].arn
    : "arn:aws:iam::${local.account_id}:oidc-provider/token.actions.githubusercontent.com"
  )
}

resource "aws_s3_bucket" "tfstate" {
  bucket = local.state_bucket

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "tfstate" {
  bucket                  = aws_s3_bucket.tfstate.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_policy" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "DenyHTTP"
      Effect    = "Deny"
      Principal = "*"
      Action    = "s3:*"
      Resource = [
        aws_s3_bucket.tfstate.arn,
        "${aws_s3_bucket.tfstate.arn}/*",
      ]
      Condition = {
        Bool = { "aws:SecureTransport" = "false" }
      }
    }]
  })
}

resource "aws_s3_bucket" "tfstate_logs" {
  bucket = "${local.state_bucket}-logs"
  lifecycle { prevent_destroy = true }
}

resource "aws_s3_bucket_versioning" "tfstate_logs" {
  bucket = aws_s3_bucket.tfstate_logs.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate_logs" {
  bucket = aws_s3_bucket.tfstate_logs.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "tfstate_logs" {
  bucket                  = aws_s3_bucket.tfstate_logs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_policy" "tfstate_logs" {
  bucket = aws_s3_bucket.tfstate_logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowLogDelivery"
        Effect    = "Allow"
        Principal = { Service = "logging.s3.amazonaws.com" }
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.tfstate_logs.arn}/tfstate/*"
        Condition = {
          ArnLike     = { "aws:SourceArn" = aws_s3_bucket.tfstate.arn }
          StringEquals = { "aws:SourceAccount" = local.account_id }
        }
      },
      {
        Sid       = "DenyHTTP"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.tfstate_logs.arn,
          "${aws_s3_bucket.tfstate_logs.arn}/*",
        ]
        Condition = {
          Bool = { "aws:SecureTransport" = "false" }
        }
      }
    ]
  })
}

resource "aws_s3_bucket_logging" "tfstate" {
  bucket        = aws_s3_bucket.tfstate.id
  target_bucket = aws_s3_bucket.tfstate_logs.id
  target_prefix = "tfstate/"
}

resource "aws_dynamodb_table" "tflock" {
  name                        = local.lock_table
  billing_mode                = "PAY_PER_REQUEST"
  hash_key                    = "LockID"
  deletion_protection_enabled = true

  attribute {
    name = "LockID"
    type = "S"
  }

  # checkov:skip=CKV_AWS_119: lock table uses DynamoDB default AWS-owned encryption; CMK provides no value here
  # checkov:skip=CKV_AWS_28: point-in-time recovery on a lock table provides no value
  point_in_time_recovery {
    enabled = false
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_iam_openid_connect_provider" "github" {
  count = var.create_oidc_provider ? 1 : 0

  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
  thumbprint_list = [
    "6938fd4d98bab03faadb97b34396831e3780aea1",
    "1c58a3a8518e8759bf075b76b750d4f2df264fcd",
  ]

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_iam_role" "github_actions" {
  name = local.role_name

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = local.oidc_provider_arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:sub" = "repo:${var.github_repo}:ref:refs/heads/main"
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy" "github_actions" {
  name = "deploy"
  role = aws_iam_role.github_actions.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "S3Buckets"
        Effect = "Allow"
        Action = [
          "s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:ListBucket",
          "s3:GetBucketPolicy", "s3:PutBucketPolicy",
          "s3:GetBucketVersioning", "s3:PutBucketVersioning",
          "s3:GetEncryptionConfiguration", "s3:PutEncryptionConfiguration",
          "s3:GetBucketPublicAccessBlock", "s3:PutBucketPublicAccessBlock",
          "s3:GetBucketTagging", "s3:PutBucketTagging",
          "s3:GetBucketAcl", "s3:PutBucketAcl",
          "s3:GetBucketObjectLockConfiguration", "s3:PutBucketObjectLockConfiguration",
          "s3:GetBucketRequestPayment",
          "s3:GetBucketWebsite", "s3:GetBucketCORS", "s3:GetAccelerateConfiguration",
          "s3:GetLifecycleConfiguration",
          "s3:CreateBucket", "s3:DeleteBucket",
        ]
        Resource = [
          "arn:aws:s3:::${local.state_bucket}",
          "arn:aws:s3:::${local.state_bucket}/*",
          "arn:aws:s3:::${var.prefix}-app-${local.account_id}",
          "arn:aws:s3:::${var.prefix}-app-${local.account_id}/*",
        ]
      },
      {
        Sid      = "DynamoLock"
        Effect   = "Allow"
        Action   = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:DeleteItem"]
        Resource = "arn:aws:dynamodb:${var.aws_region}:${local.account_id}:table/${local.lock_table}"
      },
      {
        Sid    = "IAMPrefixedRoles"
        Effect = "Allow"
        Action = [
          "iam:GetRole", "iam:CreateRole", "iam:DeleteRole",
          "iam:PutRolePolicy", "iam:DeleteRolePolicy",
          "iam:GetRolePolicy", "iam:ListRolePolicies",
          "iam:AttachRolePolicy", "iam:DetachRolePolicy",
          "iam:ListAttachedRolePolicies", "iam:ListInstanceProfilesForRole",
          "iam:TagRole", "iam:UntagRole",
        ]
        Resource = "arn:aws:iam::${local.account_id}:role/${var.prefix}-*"
      },
      {
        Sid      = "IAMPassRoleToLambda"
        Effect   = "Allow"
        Action   = "iam:PassRole"
        Resource = "arn:aws:iam::${local.account_id}:role/${var.prefix}-*"
        Condition = {
          StringEquals = { "iam:PassedToService" = "lambda.amazonaws.com" }
        }
      },
      {
        # cognito-identity:SetIdentityPoolRoles does not populate iam:PassedToService,
        # so a StringEquals condition evaluates false and blocks the call.
        # Resource scope to ${prefix}-* is the enforced boundary here.
        Sid      = "IAMPassRoleToCognito"
        Effect   = "Allow"
        Action   = "iam:PassRole"
        Resource = "arn:aws:iam::${local.account_id}:role/${var.prefix}-*"
      },
      {
        Sid    = "LambdaPrefixed"
        Effect = "Allow"
        Action = [
          "lambda:CreateFunction", "lambda:DeleteFunction", "lambda:UpdateFunctionCode",
          "lambda:UpdateFunctionConfiguration", "lambda:GetFunction", "lambda:GetFunctionConfiguration",
          "lambda:AddPermission", "lambda:RemovePermission", "lambda:GetPolicy",
          "lambda:CreateFunctionUrlConfig", "lambda:UpdateFunctionUrlConfig",
          "lambda:DeleteFunctionUrlConfig", "lambda:GetFunctionUrlConfig",
          "lambda:PublishVersion", "lambda:ListVersionsByFunction",
          "lambda:TagResource", "lambda:UntagResource", "lambda:ListTags",
        ]
        Resource = "arn:aws:lambda:${var.aws_region}:${local.account_id}:function:${var.prefix}-*"
      },
      {
        Sid    = "CognitoIdentity"
        Effect = "Allow"
        Action = [
          "cognito-identity:CreateIdentityPool", "cognito-identity:DeleteIdentityPool",
          "cognito-identity:UpdateIdentityPool", "cognito-identity:DescribeIdentityPool",
          "cognito-identity:SetIdentityPoolRoles", "cognito-identity:GetIdentityPoolRoles",
          "cognito-identity:ListIdentityPools", "cognito-identity:TagResource",
          "cognito-identity:UntagResource",
        ]
        Resource = "arn:aws:cognito-identity:${var.aws_region}:${local.account_id}:identitypool/*"
      },
      {
        Sid    = "CloudFront"
        Effect = "Allow"
        Action = [
          "cloudfront:CreateDistribution", "cloudfront:UpdateDistribution",
          "cloudfront:DeleteDistribution", "cloudfront:GetDistribution",
          "cloudfront:GetDistributionConfig", "cloudfront:ListDistributions",
          "cloudfront:CreateInvalidation", "cloudfront:GetInvalidation",
          "cloudfront:CreateOriginAccessControl", "cloudfront:UpdateOriginAccessControl",
          "cloudfront:DeleteOriginAccessControl", "cloudfront:GetOriginAccessControl",
          "cloudfront:ListOriginAccessControls",
          "cloudfront:CreateFunction", "cloudfront:UpdateFunction", "cloudfront:DeleteFunction",
          "cloudfront:DescribeFunction", "cloudfront:GetFunction", "cloudfront:PublishFunction",
          "cloudfront:ListFunctions",
          "cloudfront:TagResource", "cloudfront:UntagResource", "cloudfront:ListTagsForResource",
        ]
        # CloudFront create/associate actions don't support resource-level restrictions
        Resource = "*"
      },
      {
        Sid    = "WAFv2"
        Effect = "Allow"
        Action = [
          "wafv2:CreateWebACL", "wafv2:UpdateWebACL", "wafv2:DeleteWebACL",
          "wafv2:GetWebACL", "wafv2:ListWebACLs",
          "wafv2:AssociateWebACL", "wafv2:DisassociateWebACL", "wafv2:GetWebACLForResource",
          "wafv2:CreateIPSet", "wafv2:UpdateIPSet", "wafv2:DeleteIPSet",
          "wafv2:GetIPSet", "wafv2:ListIPSets",
          "wafv2:TagResource", "wafv2:UntagResource", "wafv2:ListTagsForResource",
          "wafv2:PutLoggingConfiguration", "wafv2:GetLoggingConfiguration",
          "wafv2:DeleteLoggingConfiguration", "wafv2:ListResourcesForWebACL",
          "wafv2:CheckCapacity",
        ]
        # WAF create/associate actions don't support resource-level restrictions
        Resource = "*"
      },
      {
        Sid    = "CloudWatchLogsLambda"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup", "logs:DeleteLogGroup",
          "logs:PutRetentionPolicy", "logs:DescribeLogGroups",
          "logs:TagResource", "logs:UntagResource", "logs:ListTagsLogGroup",
        ]
        Resource = "arn:aws:logs:${var.aws_region}:${local.account_id}:log-group:/aws/lambda/${var.prefix}-*"
      },
      {
        Sid    = "CloudWatchLogsWAF"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup", "logs:DeleteLogGroup",
          "logs:PutRetentionPolicy", "logs:DescribeLogGroups",
          "logs:PutResourcePolicy", "logs:DeleteResourcePolicy",
          "logs:DescribeResourcePolicies",
        ]
        Resource = "arn:aws:logs:us-east-1:${local.account_id}:log-group:aws-waf-logs-${var.prefix}:*"
      },
      {
        Sid    = "Budgets"
        Effect = "Allow"
        Action = [
          "budgets:CreateBudget", "budgets:ModifyBudget", "budgets:DeleteBudget",
          "budgets:ViewBudget", "budgets:DescribeBudget",
          "budgets:CreateNotification", "budgets:UpdateNotification", "budgets:DeleteNotification",
          "budgets:DescribeNotificationsForBudget",
          "budgets:CreateSubscriber", "budgets:UpdateSubscriber", "budgets:DeleteSubscriber",
          "budgets:DescribeSubscribersForNotification",
        ]
        Resource = "arn:aws:budgets::${local.account_id}:budget/${var.prefix}-*"
      },
    ]
  })
}
