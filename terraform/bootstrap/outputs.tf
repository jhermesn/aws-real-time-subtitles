output "github_secrets" {
  description = "Add these in GitHub → Settings → Secrets → Actions"
  value = {
    AWS_ACCOUNT_ID = local.account_id
    SIGNING_SECRET = "(generate with: openssl rand -hex 32)"
  }
}

output "github_variables" {
  description = "Add these in GitHub → Settings → Variables → Actions"
  value = {
    TF_PREFIX       = var.prefix
    AWS_REGION      = var.aws_region
    TF_STATE_BUCKET = local.state_bucket
    AWS_ROLE_ARN    = module.github_actions_role.arn
    ADMIN_IPS       = "(your public IP + /32, check: curl -s https://checkip.amazonaws.com)"
  }
}
