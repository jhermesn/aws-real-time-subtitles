resource "aws_budgets_budget" "monthly" {
  count        = var.alert_email != "" ? 1 : 0
  name         = "${var.prefix}-monthly"
  budget_type  = "COST"
  limit_amount = "5"
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 50
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.alert_email]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.alert_email]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = [var.alert_email]
  }
}

# Cost Anomaly Detection reacts within hours of an unusual spend pattern.
# The Budget notification above only fires once actual/forecasted spend
# crosses a fixed percentage, which can lag up to 24h behind the anomaly
# itself. Free service, no additional cost.
#
# AWS caps SERVICE-dimensional monitors at 1 per account and auto-creates
# one ("Default-Services-Monitor") for every account already; there's no
# Terraform data source to look it up, so its ARN is fetched via the AWS
# CLI at plan/apply time instead of creating a competing monitor that would
# fail against that same quota.
data "external" "default_ce_monitor" {
  count = var.alert_email != "" ? 1 : 0

  program = ["${path.module}/scripts/default-ce-monitor.sh"]
}

resource "aws_ce_anomaly_subscription" "monthly" {
  provider = aws.us_east_1
  count    = var.alert_email != "" ? 1 : 0

  name = "${var.prefix}-anomaly-alert"
  # IMMEDIATE frequency only supports SNS topic subscribers, not direct email.
  frequency = "DAILY"

  monitor_arn_list = [data.external.default_ce_monitor[0].result.arn]

  subscriber {
    type    = "EMAIL"
    address = var.alert_email
  }

  threshold_expression {
    dimension {
      key           = "ANOMALY_TOTAL_IMPACT_ABSOLUTE"
      match_options = ["GREATER_THAN_OR_EQUAL"]
      values        = ["10"]
    }
  }
}
