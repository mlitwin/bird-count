# Monthly cost budget with email alerts at 80% and 100% of threshold.
# Only created when alarm_email is set (prod); dev has no alarm_email by default.

resource "aws_budgets_budget" "monthly" {
  count = var.alarm_email != "" ? 1 : 0

  name         = "${local.project_name}-${var.environment}-monthly"
  budget_type  = "COST"
  limit_amount = tostring(var.budget_amount)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.alarm_email]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.alarm_email]
  }
}
