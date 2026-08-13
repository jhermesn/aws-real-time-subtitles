resource "aws_wafv2_ip_set" "admin" {
  provider = aws.us_east_1
  count    = var.enable_waf ? 1 : 0

  name               = "${var.prefix}-admin-ips"
  scope              = "CLOUDFRONT"
  ip_address_version = "IPV4"
  addresses          = var.admin_ips

  tags = { prefix = var.prefix }
}

resource "aws_wafv2_ip_set" "admin_v6" {
  provider = aws.us_east_1
  count    = var.enable_waf && length(var.admin_ips_v6) > 0 ? 1 : 0

  name               = "${var.prefix}-admin-ips-v6"
  scope              = "CLOUDFRONT"
  ip_address_version = "IPV6"
  addresses          = var.admin_ips_v6

  tags = { prefix = var.prefix }
}

# Optional, off by default: the speaker-auth CloudFront Function already
# enforces the IP allowlist and room-token checks at the edge for free.
# This adds AWSManagedRulesKnownBadInputsRuleSet and a duplicate (defense in
# depth) IP-allowlist rule.
resource "aws_wafv2_web_acl" "main" {
  provider = aws.us_east_1
  count    = var.enable_waf ? 1 : 0

  name  = "${var.prefix}-acl"
  scope = "CLOUDFRONT"
  tags  = { prefix = var.prefix }

  default_action {
    allow {}
  }

  rule {
    name     = "aws-known-bad-inputs"
    priority = 0

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.prefix}-known-bad-inputs"
      sampled_requests_enabled   = true
    }
  }

  # /api/session is reachable by attendee (non-admin) IPs; it's gated by the
  # signed room token instead (see CloudFront Function speaker-auth and the
  # sign-room Lambda), not by IP allowlist. This rule must sit at a lower
  # priority number than block-protected-paths so it terminates evaluation
  # first: WAFv2 stops at the first rule with a terminating action.
  rule {
    name     = "allow-api-session"
    priority = 1

    action {
      allow {}
    }

    statement {
      byte_match_statement {
        field_to_match {
          uri_path {}
        }
        positional_constraint = "EXACTLY"
        search_string         = "/api/session"
        text_transformation {
          priority = 0
          type     = "NONE"
        }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.prefix}-allow-api-session"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "block-protected-paths"
    priority = 2

    action {
      block {}
    }

    statement {
      and_statement {
        statement {
          or_statement {
            statement {
              byte_match_statement {
                field_to_match {
                  uri_path {}
                }
                positional_constraint = "STARTS_WITH"
                search_string         = "/admin"
                text_transformation {
                  priority = 0
                  type     = "NONE"
                }
              }
            }
            statement {
              byte_match_statement {
                field_to_match {
                  uri_path {}
                }
                positional_constraint = "STARTS_WITH"
                search_string         = "/api"
                text_transformation {
                  priority = 0
                  type     = "NONE"
                }
              }
            }
          }
        }
        statement {
          not_statement {
            statement {
              or_statement {
                statement {
                  ip_set_reference_statement {
                    arn = aws_wafv2_ip_set.admin[0].arn
                  }
                }
                dynamic "statement" {
                  for_each = length(var.admin_ips_v6) > 0 ? [1] : []
                  content {
                    ip_set_reference_statement {
                      arn = aws_wafv2_ip_set.admin_v6[0].arn
                    }
                  }
                }
              }
            }
          }
        }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.prefix}-block-protected-paths"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.prefix}-waf-acl"
    sampled_requests_enabled   = true
  }
}
