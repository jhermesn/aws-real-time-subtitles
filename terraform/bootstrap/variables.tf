variable "prefix" {
  description = "Short identifier for all resource names, must match the one used in terraform/"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]{1,20}$", var.prefix))
    error_message = "prefix must be lowercase alphanumeric + hyphens, max 20 chars"
  }
}

variable "aws_region" {
  description = "AWS region for state bucket and DynamoDB lock table"
  type        = string
  default     = "us-east-1"
}

variable "github_repo" {
  description = "GitHub repository in owner/repo format (e.g. myorg/aws-real-time-subtitles)"
  type        = string
}

variable "create_oidc_provider" {
  description = "Set to false if the GitHub OIDC provider already exists in this AWS account"
  type        = bool
  default     = true
}
