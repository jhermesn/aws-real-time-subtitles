variable "prefix" {
  description = "Short identifier for all resource names (e.g. myevent)"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]{1,20}$", var.prefix))
    error_message = "prefix must be lowercase alphanumeric + hyphens, max 20 chars"
  }
}

variable "aws_region" {
  description = "AWS region for all resources (WAF is always us-east-1 regardless of this setting)"
  type        = string
  default     = "us-east-1"
}

variable "github_repo" {
  description = "GitHub repository in owner/repo format (e.g. myorg/aws-real-time-subtitles)"
  type        = string
}

variable "admin_ips" {
  description = "CIDR blocks allowed to access /admin and /api (organizer public IPs)"
  type        = list(string)

  validation {
    condition     = length(var.admin_ips) > 0
    error_message = "admin_ips must contain at least one CIDR"
  }
}

variable "alert_email" {
  description = "Email address for AWS Budgets cost alert, leave empty to skip budget creation"
  type        = string
  default     = ""
}

variable "signing_secret" {
  description = "HMAC-SHA256 secret for speaker token signing; set via TF_VAR_signing_secret, never commit"
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.signing_secret) >= 32
    error_message = "signing_secret must be at least 32 characters"
  }
}
