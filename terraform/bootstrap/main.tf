terraform {
  required_version = ">= 1.10"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.28"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
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
  account_id   = data.aws_caller_identity.current.account_id
  state_bucket = "${var.prefix}-tfstate-${local.account_id}"
  role_name    = "${var.prefix}-github-actions"
  oidc_provider_arn = (
    var.create_oidc_provider
    ? module.github_oidc.arn
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
          ArnLike      = { "aws:SourceArn" = aws_s3_bucket.tfstate.arn }
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

module "github_oidc" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-oidc-provider"
  version = "~> 6.0"

  create = var.create_oidc_provider

  url = "https://token.actions.githubusercontent.com"
  # client_id_list defaults to ["sts.amazonaws.com"] when omitted, matching
  # the previous hardcoded value. thumbprint_list is fetched live from the
  # provider's own TLS cert instead of hardcoded, avoiding staleness when
  # GitHub rotates its cert chain.

  tags = { Project = var.prefix, ManagedBy = "terraform" }
}

module "github_actions_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role"
  version = "~> 6.0"

  name            = local.role_name
  use_name_prefix = false

  trust_policy_permissions = {
    GitHubOIDC = {
      actions = ["sts:AssumeRoleWithWebIdentity"]
      principals = [{
        type        = "Federated"
        identifiers = [local.oidc_provider_arn]
      }]
      condition = [
        {
          test     = "StringEquals"
          variable = "token.actions.githubusercontent.com:sub"
          values   = ["repo:${var.github_repo}:ref:refs/heads/main"]
        },
        {
          test     = "StringEquals"
          variable = "token.actions.githubusercontent.com:aud"
          values   = ["sts.amazonaws.com"]
        },
      ]
    }
  }

  tags = { Project = var.prefix, ManagedBy = "terraform" }
}

# Kept as a standalone resource (not module-managed inline_policy_permissions)
# so its name stays "deploy"; the module always names the inline policy after
# the role, which would force a destroy/recreate of a policy that's already
# attached to a live role for no functional benefit.
resource "aws_iam_role_policy" "github_actions" {
  name = "deploy"
  role = module.github_actions_role.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # s3:* scoped to the two specific known bucket ARNs, not a wildcard on all buckets
        Sid    = "S3Buckets"
        Effect = "Allow"
        Action = "s3:*"
        Resource = [
          "arn:aws:s3:::${local.state_bucket}",
          "arn:aws:s3:::${local.state_bucket}/*",
          "arn:aws:s3:::${var.prefix}-app-${local.account_id}",
          "arn:aws:s3:::${var.prefix}-app-${local.account_id}/*",
        ]
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
        Sid      = "LambdaPrefixed"
        Effect   = "Allow"
        Action   = "lambda:*"
        Resource = "arn:aws:lambda:${var.aws_region}:${local.account_id}:function:${var.prefix}-*"
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
          "wafv2:ListResourcesForWebACL", "wafv2:CheckCapacity",
        ]
        # WAF create/associate actions don't support resource-level restrictions
        Resource = "*"
      },
      {
        Sid    = "CloudWatchLogsLambda"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup", "logs:DeleteLogGroup",
          "logs:DescribeLogGroups",
          "logs:PutRetentionPolicy",
          "logs:TagResource", "logs:UntagResource",
          "logs:ListTagsLogGroup", "logs:ListTagsForResource",
        ]
        Resource = "arn:aws:logs:${var.aws_region}:${local.account_id}:log-group:/aws/lambda/${var.prefix}-*"
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
      {
        # Cost Explorer anomaly detection actions don't support resource-level
        # restrictions.
        # ce:GetAnomalyMonitors looks up the account's AWS-managed default
        # SERVICE monitor (1-per-account quota, auto-created by AWS) instead
        # of creating a competing one.
        Sid    = "CostAnomalyDetection"
        Effect = "Allow"
        Action = [
          "ce:GetAnomalyMonitors",
          "ce:CreateAnomalySubscription", "ce:UpdateAnomalySubscription", "ce:DeleteAnomalySubscription",
          "ce:GetAnomalySubscriptions",
          "ce:TagResource", "ce:UntagResource", "ce:ListTagsForResource",
        ]
        Resource = "*"
      },
    ]
  })
}
